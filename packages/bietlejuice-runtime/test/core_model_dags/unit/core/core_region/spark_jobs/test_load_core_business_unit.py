"""Unit tests for CoreBusinessUnitSparkJob (current-state core models).

Covers both output tables built from the narrow history tables via CurrentStateBuilder:
  - business_unit             (grain id_business_unit)
  - business_unit_region      (grain id_region + id_business_unit)

Key behaviours asserted:
  - one row per grain (current state),
  - attributes pivoted to their latest value,
  - ts_created = the *latest* ev_ts_created value (current state, not earliest),
  - ts_updated = MAX(ts_transaction),
  - (0,0)/null-key sentinel filtered out for business_unit_region,
  - surrogate key equals the history sha256 basis.
"""

import hashlib
from datetime import datetime
from types import SimpleNamespace
from unittest.mock import patch

import pytest
from pyspark.sql.types import (
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from dags.core.core_region.spark_jobs.load_core_business_unit import (
    CoreBusinessUnitSparkJob,
)

_MODULE = "dags.core.core_region.spark_jobs.load_core_business_unit"

EXPECTED_BU_COLUMNS = {
    "sk_core_business_unit",
    "id_business_unit",
    "hub_name",
    "business_context",
    "sdr_type",
    "negotiation_type",
    "lead_types",
    "operational_context",
    "ts_business_unit_created",
    "ts_business_unit_updated",
    "ts_load",
    "year",
    "month",
    "day",
}

EXPECTED_BUR_COLUMNS = {
    "sk_core_business_unit_region",
    "id_region",
    "id_business_unit",
    "business_context",
    "ts_business_unit_region_created",
    "ts_business_unit_region_updated",
    "ts_load",
    "year",
    "month",
    "day",
}

BU_EVENT_CONFIGS = [
    {"target_col": "hub_name", "target_type": "string"},
    {"target_col": "sdr_type", "target_type": "string"},
    {"target_col": "lead_types", "target_type": "string"},
    {"target_col": "negotiation_type", "target_type": "string"},
    {"target_col": "operational_context", "target_type": "string"},
    {"target_col": "business_context", "target_type": "string"},
    {
        "target_col": "ts_business_unit_created",
        "target_type": "timestamp",
        "event_name": "ev_ts_created",
    },
]

BUR_EVENT_CONFIGS = [
    {"target_col": "business_context", "target_type": "string"},
    {
        "target_col": "ts_business_unit_region_created",
        "target_type": "timestamp",
        "event_name": "ev_ts_created",
    },
]

CONFIG_MAP_BU = {
    "BUSINESS_UNIT_HISTORY_TABLE": "test.business_unit_history",
    "business_unit_event_configs": BU_EVENT_CONFIGS,
}

CONFIG_MAP_BUR = {
    "BUSINESS_UNIT_REGION_HISTORY_TABLE": "test.business_unit_region_history",
    "business_unit_region_event_configs": BUR_EVENT_CONFIGS,
}


def _sha256_sk(*parts: str) -> str:
    return hashlib.sha256("||".join(parts).encode("utf-8")).hexdigest()


def _config_side_effect(config_map):
    def _side_effect(key, required=True, default=None):
        if key in config_map:
            return config_map[key]
        if required:
            raise KeyError(f"Missing required config key: {key}")
        return default

    return _side_effect


def _make_args(table_name):
    return SimpleNamespace(
        table_name=table_name,
        load_start_date=None,
        load_end_date=None,
    )


# ---------------------------------------------------------------------------
# Fixtures: narrow history DataFrames (id_*, event_name, value, ts_transaction)
# ---------------------------------------------------------------------------


@pytest.fixture
def bu_history_df(spark_session):
    schema = StructType(
        [
            StructField("id_business_unit", StringType(), True),
            StructField("event_name", StringType(), True),
            StructField("value", StringType(), True),
            StructField("ts_transaction", TimestampType(), True),
        ]
    )
    data = [
        # hub 1 — name changes; latest is "Hub Sao Paulo"
        ("1", "ev_hub_name", "Hub SP", datetime(2024, 3, 1, 8, 0, 0)),
        ("1", "ev_hub_name", "Hub Sao Paulo", datetime(2024, 3, 10, 9, 0, 0)),
        ("1", "ev_sdr_type", "SDR_A", datetime(2024, 3, 1, 8, 0, 0)),
        ("1", "ev_lead_types", "[sale,rent]", datetime(2024, 3, 1, 8, 0, 0)),
        ("1", "ev_negotiation_type", "STANDARD", datetime(2024, 3, 1, 8, 0, 0)),
        ("1", "ev_operational_context", "SAO_PAULO", datetime(2024, 3, 1, 8, 0, 0)),
        ("1", "ev_business_context", "SALE", datetime(2024, 3, 1, 8, 0, 0)),
        (
            "1",
            "ev_ts_created",
            "2022-07-13 19:51:35.816",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        # hub 2 — minimal
        ("2", "ev_hub_name", "Hub RJ", datetime(2024, 2, 1, 8, 0, 0)),
        ("2", "ev_business_context", "RENT", datetime(2024, 2, 1, 8, 0, 0)),
        (
            "2",
            "ev_ts_created",
            "2023-01-01 00:00:00.000",
            datetime(2024, 2, 1, 8, 0, 0),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def bur_history_df(spark_session):
    schema = StructType(
        [
            StructField("id_region", StringType(), True),
            StructField("id_business_unit", StringType(), True),
            StructField("event_name", StringType(), True),
            StructField("value", StringType(), True),
            StructField("ts_transaction", TimestampType(), True),
        ]
    )
    data = [
        # pair (10, 20) — context flips SALE->RENT; ts_created has an OLD value then a
        # NEWER value at a LATER ts_transaction (current state must take the latest).
        ("10", "20", "ev_business_context", "SALE", datetime(2024, 3, 1, 8, 0, 0)),
        ("10", "20", "ev_business_context", "RENT", datetime(2024, 3, 5, 10, 0, 0)),
        (
            "10",
            "20",
            "ev_ts_created",
            "2024-01-10 00:00:00.000",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        (
            "10",
            "20",
            "ev_ts_created",
            "2025-06-02 00:00:00.000",
            datetime(2024, 3, 20, 11, 0, 0),
        ),
        # pair (11, 21) — single association
        ("11", "21", "ev_business_context", "SALE", datetime(2024, 4, 1, 8, 0, 0)),
        (
            "11",
            "21",
            "ev_ts_created",
            "2024-04-01 08:00:00.000",
            datetime(2024, 4, 1, 8, 0, 0),
        ),
        # (0,0) sentinel — must be filtered out
        (
            "0",
            "0",
            "ev_ts_created",
            "1970-01-01 00:00:00.000",
            datetime(2024, 1, 1, 0, 0, 0),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


# ---------------------------------------------------------------------------
# business_unit
# ---------------------------------------------------------------------------


class TestBusinessUnit:
    def _run(self, spark_session, bu_history_df):
        job = CoreBusinessUnitSparkJob()
        args = _make_args("business_unit")
        with (
            patch.object(
                CoreBusinessUnitSparkJob,
                "get_config",
                side_effect=_config_side_effect(CONFIG_MAP_BU),
            ),
            patch.object(spark_session, "table", return_value=bu_history_df),
        ):
            return job.create_core_model(spark_session, args)

    def test_column_names_match_schema(self, spark_session, bu_history_df):
        result = self._run(spark_session, bu_history_df)
        assert set(result.columns) == EXPECTED_BU_COLUMNS
        assert len(result.columns) == 14

    def test_one_row_per_grain(self, spark_session, bu_history_df):
        result = self._run(spark_session, bu_history_df)
        rows = result.collect()
        ids = [r["id_business_unit"] for r in rows]
        assert sorted(ids) == [1, 2]
        assert len(ids) == len(set(ids))

    def test_attribute_is_latest_value(self, spark_session, bu_history_df):
        result = self._run(spark_session, bu_history_df)
        hub1 = next(r for r in result.collect() if r["id_business_unit"] == 1)
        assert hub1["hub_name"] == "Hub Sao Paulo"
        assert hub1["business_context"] == "SALE"
        assert hub1["sdr_type"] == "SDR_A"

    def test_ts_created_and_updated(self, spark_session, bu_history_df):
        result = self._run(spark_session, bu_history_df)
        hub1 = next(r for r in result.collect() if r["id_business_unit"] == 1)
        assert hub1["ts_business_unit_created"] == datetime(
            2022, 7, 13, 19, 51, 35, 816000
        )
        assert hub1["ts_business_unit_updated"] == datetime(2024, 3, 10, 9, 0, 0)

    def test_surrogate_key_matches_history_basis(self, spark_session, bu_history_df):
        result = self._run(spark_session, bu_history_df)
        hub1 = next(r for r in result.collect() if r["id_business_unit"] == 1)
        assert hub1["sk_core_business_unit"] == _sha256_sk("BUSINESS_UNIT", "1")


# ---------------------------------------------------------------------------
# business_unit_region
# ---------------------------------------------------------------------------


class TestBusinessUnitRegion:
    def _run(self, spark_session, bur_history_df):
        job = CoreBusinessUnitSparkJob()
        args = _make_args("business_unit_region")
        with (
            patch.object(
                CoreBusinessUnitSparkJob,
                "get_config",
                side_effect=_config_side_effect(CONFIG_MAP_BUR),
            ),
            patch.object(spark_session, "table", return_value=bur_history_df),
        ):
            return job.create_core_model(spark_session, args)

    def test_column_names_match_schema(self, spark_session, bur_history_df):
        result = self._run(spark_session, bur_history_df)
        assert set(result.columns) == EXPECTED_BUR_COLUMNS
        assert len(result.columns) == 10

    def test_zero_key_sentinel_is_filtered(self, spark_session, bur_history_df):
        result = self._run(spark_session, bur_history_df)
        keys = {(r["id_region"], r["id_business_unit"]) for r in result.collect()}
        assert (0, 0) not in keys
        assert keys == {(10, 20), (11, 21)}

    def test_ts_created_is_latest_not_earliest(self, spark_session, bur_history_df):
        """The pair (10,20) has two ev_ts_created values; current state takes the later one."""
        result = self._run(spark_session, bur_history_df)
        pair = next(
            r
            for r in result.collect()
            if r["id_region"] == 10 and r["id_business_unit"] == 20
        )
        assert pair["ts_business_unit_region_created"] == datetime(2025, 6, 2, 0, 0, 0)
        assert pair["business_context"] == "RENT"
        assert pair["ts_business_unit_region_updated"] == datetime(
            2024, 3, 20, 11, 0, 0
        )

    def test_surrogate_key_matches_history_basis(self, spark_session, bur_history_df):
        result = self._run(spark_session, bur_history_df)
        pair = next(
            r
            for r in result.collect()
            if r["id_region"] == 10 and r["id_business_unit"] == 20
        )
        assert pair["sk_core_business_unit_region"] == _sha256_sk(
            "BUSINESS_UNIT_REGION", "10", "20"
        )


# ---------------------------------------------------------------------------
# Unsupported table guard
# ---------------------------------------------------------------------------


class TestUnsupportedTable:
    def test_raises_value_error_for_unknown_table_name(self, spark_session):
        job = CoreBusinessUnitSparkJob()
        args = _make_args("nonexistent_table")
        with pytest.raises(ValueError, match="Unsupported table_name"):
            job.create_core_model(spark_session, args)
