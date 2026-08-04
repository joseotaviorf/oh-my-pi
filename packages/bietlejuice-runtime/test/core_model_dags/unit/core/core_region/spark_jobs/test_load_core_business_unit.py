"""Unit tests for CoreBusinessUnitSparkJob (current-state core models).

Covers both output tables built from the narrow history tables via CurrentStateBuilder:
  - business_unit             (grain id_business_unit)
  - business_unit_region      (grain id_business_unit_region)

Key behaviours asserted:
  - one row per grain (current state),
  - attributes pivoted to their latest value,
  - ts_created = the *latest* ev_ts_created value (current state, not earliest),
  - ts_updated = MAX(ts_transaction),
  - null/zero junction and FK keys filtered out for business_unit_region,
  - denormalized id_region/id_business_unit joined from latest history row,
  - one row per (id_region, id_business_unit) keeping highest id_business_unit_region,
  - surrogate key equals the history sha256 basis for the winning junction id.
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
    "id_business_unit_region",
    "id_region",
    "id_business_unit",
    "business_context",
    "ts_business_unit_region_created",
    "ts_business_unit_region_updated",
    "ts_load",
    "year",
    "month",
    "day",
    # Merge-control column: present on the source frame, withheld from the merge maps.
    "is_deleted",
}

# The 11 columns that must reach the published table.
PUBLISHED_BUR_COLUMNS = EXPECTED_BUR_COLUMNS - {"is_deleted"}

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
    {"target_col": "is_deleted", "target_type": "boolean"},
]

CONFIG_MAP_BU = {
    "BUSINESS_UNIT_HISTORY_TABLE": "test.business_unit_history",
    "business_unit_event_configs": BU_EVENT_CONFIGS,
    "business_unit_merge_on": ["id_business_unit"],
}

CONFIG_MAP_BUR = {
    "BUSINESS_UNIT_REGION_HISTORY_TABLE": "test.business_unit_region_history",
    "business_unit_region_event_configs": BUR_EVENT_CONFIGS,
    "business_unit_region_merge_on": ["id_region", "id_business_unit"],
    "business_unit_region_when_matched_delete_condition": "source.is_deleted = true",
    "business_unit_region_when_not_matched_insert_condition": (
        "source.is_deleted IS NULL OR source.is_deleted = false"
    ),
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
            StructField("id_business_unit_region", StringType(), True),
            StructField("id_region", StringType(), True),
            StructField("id_business_unit", StringType(), True),
            StructField("event_name", StringType(), True),
            StructField("value", StringType(), True),
            StructField("ts_transaction", TimestampType(), True),
        ]
    )
    data = [
        # junction 100 — context flips SALE->RENT; ts_created has an OLD value then a
        # NEWER value at a LATER ts_transaction (current state must take the latest).
        (
            "100",
            "10",
            "20",
            "ev_business_context",
            "SALE",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        (
            "100",
            "10",
            "20",
            "ev_business_context",
            "RENT",
            datetime(2024, 3, 5, 10, 0, 0),
        ),
        (
            "100",
            "10",
            "20",
            "ev_ts_created",
            "2024-01-10 00:00:00.000",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        (
            "100",
            "10",
            "20",
            "ev_ts_created",
            "2025-06-02 00:00:00.000",
            datetime(2024, 3, 20, 11, 0, 0),
        ),
        # junction 101 — single association
        (
            "101",
            "11",
            "21",
            "ev_business_context",
            "SALE",
            datetime(2024, 4, 1, 8, 0, 0),
        ),
        (
            "101",
            "11",
            "21",
            "ev_ts_created",
            "2024-04-01 08:00:00.000",
            datetime(2024, 4, 1, 8, 0, 0),
        ),
        # (0,0) sentinel junction — must be filtered out
        (
            "999",
            "0",
            "0",
            "ev_ts_created",
            "1970-01-01 00:00:00.000",
            datetime(2024, 1, 1, 0, 0, 0),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def bur_history_reassociation_df(spark_session):
    """Two junction ids for the same (region, business_unit) pair."""
    schema = StructType(
        [
            StructField("id_business_unit_region", StringType(), True),
            StructField("id_region", StringType(), True),
            StructField("id_business_unit", StringType(), True),
            StructField("event_name", StringType(), True),
            StructField("value", StringType(), True),
            StructField("ts_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "100",
            "10",
            "20",
            "ev_business_context",
            "SALE",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        (
            "100",
            "10",
            "20",
            "ev_ts_created",
            "2024-03-01 08:00:00.000",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        (
            "102",
            "10",
            "20",
            "ev_business_context",
            "RENT",
            datetime(2024, 6, 1, 9, 0, 0),
        ),
        (
            "102",
            "10",
            "20",
            "ev_ts_created",
            "2024-06-01 09:00:00.000",
            datetime(2024, 6, 1, 9, 0, 0),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def bur_history_stale_sibling_df(spark_session):
    """Stale low junction id vs live high id for the same pair (prod-like pattern)."""
    schema = StructType(
        [
            StructField("id_business_unit_region", StringType(), True),
            StructField("id_region", StringType(), True),
            StructField("id_business_unit", StringType(), True),
            StructField("event_name", StringType(), True),
            StructField("value", StringType(), True),
            StructField("ts_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "3277",
            "2",
            "138",
            "ev_business_context",
            "SALE",
            datetime(2024, 1, 1, 8, 0, 0),
        ),
        (
            "3277",
            "2",
            "138",
            "ev_ts_created",
            "2024-01-01 08:00:00.000",
            datetime(2024, 1, 1, 8, 0, 0),
        ),
        (
            "7214",
            "2",
            "138",
            "ev_business_context",
            "RENT",
            datetime(2024, 6, 15, 10, 0, 0),
        ),
        (
            "7214",
            "2",
            "138",
            "ev_ts_created",
            "2024-06-15 10:00:00.000",
            datetime(2024, 6, 15, 10, 0, 0),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def bur_history_deleted_sibling_df(spark_session):
    """A pair holding a live junction and a deleted one with a *higher* junction id.

    The pair is still live, so the live junction must win even though it loses on id —
    without live preference the deleted junction would win and the pair be dropped.
    """
    schema = StructType(
        [
            StructField("id_business_unit_region", StringType(), True),
            StructField("id_region", StringType(), True),
            StructField("id_business_unit", StringType(), True),
            StructField("event_name", StringType(), True),
            StructField("value", StringType(), True),
            StructField("ts_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "200",
            "5",
            "50",
            "ev_business_context",
            "SALE",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        (
            "200",
            "5",
            "50",
            "ev_ts_created",
            "2024-03-01 08:00:00.000",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        ("200", "5", "50", "ev_is_deleted", "false", datetime(2024, 3, 1, 8, 0, 0)),
        (
            "300",
            "5",
            "50",
            "ev_business_context",
            "RENT",
            datetime(2024, 4, 1, 8, 0, 0),
        ),
        (
            "300",
            "5",
            "50",
            "ev_ts_created",
            "2024-04-01 08:00:00.000",
            datetime(2024, 4, 1, 8, 0, 0),
        ),
        ("300", "5", "50", "ev_is_deleted", "false", datetime(2024, 4, 1, 8, 0, 0)),
        ("300", "5", "50", "ev_is_deleted", "true", datetime(2024, 5, 1, 8, 0, 0)),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def bur_history_unobserved_sibling_df(spark_session):
    """A pair holding a junction with no ev_is_deleted event and a live one above it.

    Both junctions are live, so the highest id must win. The unobserved junction is what
    every junction looks like until the ev_is_deleted backfill reaches it, and it must not
    outrank an observed live sibling just because its state is null.
    """
    schema = StructType(
        [
            StructField("id_business_unit_region", StringType(), True),
            StructField("id_region", StringType(), True),
            StructField("id_business_unit", StringType(), True),
            StructField("event_name", StringType(), True),
            StructField("value", StringType(), True),
            StructField("ts_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "500",
            "7",
            "70",
            "ev_business_context",
            "SALE",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        (
            "500",
            "7",
            "70",
            "ev_ts_created",
            "2024-03-01 08:00:00.000",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        (
            "600",
            "7",
            "70",
            "ev_business_context",
            "RENT",
            datetime(2024, 4, 1, 8, 0, 0),
        ),
        (
            "600",
            "7",
            "70",
            "ev_ts_created",
            "2024-04-01 08:00:00.000",
            datetime(2024, 4, 1, 8, 0, 0),
        ),
        ("600", "7", "70", "ev_is_deleted", "false", datetime(2024, 4, 1, 8, 0, 0)),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def bur_history_deleted_pair_df(spark_session):
    """A pair whose only junction was deleted — the merge must remove it."""
    schema = StructType(
        [
            StructField("id_business_unit_region", StringType(), True),
            StructField("id_region", StringType(), True),
            StructField("id_business_unit", StringType(), True),
            StructField("event_name", StringType(), True),
            StructField("value", StringType(), True),
            StructField("ts_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "400",
            "6",
            "60",
            "ev_business_context",
            "SALE",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        (
            "400",
            "6",
            "60",
            "ev_ts_created",
            "2024-03-01 08:00:00.000",
            datetime(2024, 3, 1, 8, 0, 0),
        ),
        ("400", "6", "60", "ev_is_deleted", "false", datetime(2024, 3, 1, 8, 0, 0)),
        ("400", "6", "60", "ev_is_deleted", "true", datetime(2024, 6, 1, 8, 0, 0)),
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
    def _run(self, spark_session, history_df):
        job = CoreBusinessUnitSparkJob()
        args = _make_args("business_unit_region")
        with (
            patch.object(
                CoreBusinessUnitSparkJob,
                "get_config",
                side_effect=_config_side_effect(CONFIG_MAP_BUR),
            ),
            patch.object(spark_session, "table", return_value=history_df),
        ):
            return job.create_core_model(spark_session, args)

    def test_column_names_match_schema(self, spark_session, bur_history_df):
        result = self._run(spark_session, bur_history_df)
        assert set(result.columns) == EXPECTED_BUR_COLUMNS
        assert len(result.columns) == 12

    def test_missing_ev_is_deleted_yields_null_not_deleted(
        self, spark_session, bur_history_df
    ):
        """History predating ev_is_deleted leaves NULL, which both merge conditions read as live."""
        result = self._run(spark_session, bur_history_df)
        assert {r["is_deleted"] for r in result.collect()} == {None}

    def test_zero_key_sentinel_is_filtered(self, spark_session, bur_history_df):
        result = self._run(spark_session, bur_history_df)
        junction_ids = {r["id_business_unit_region"] for r in result.collect()}
        assert 999 not in junction_ids
        assert 0 not in junction_ids
        assert junction_ids == {100, 101}

    def test_ts_created_is_latest_not_earliest(self, spark_session, bur_history_df):
        """Junction 100 has two ev_ts_created values; current state takes the later one."""
        result = self._run(spark_session, bur_history_df)
        row = next(r for r in result.collect() if r["id_business_unit_region"] == 100)
        assert row["ts_business_unit_region_created"] == datetime(2025, 6, 2, 0, 0, 0)
        assert row["business_context"] == "RENT"
        assert row["id_region"] == 10
        assert row["id_business_unit"] == 20
        assert row["ts_business_unit_region_updated"] == datetime(2024, 3, 20, 11, 0, 0)

    def test_surrogate_key_matches_history_basis(self, spark_session, bur_history_df):
        result = self._run(spark_session, bur_history_df)
        row = next(r for r in result.collect() if r["id_business_unit_region"] == 100)
        assert row["sk_core_business_unit_region"] == _sha256_sk(
            "BUSINESS_UNIT_REGION", "100"
        )

    def test_same_pair_keeps_highest_junction_id(
        self, spark_session, bur_history_reassociation_df
    ):
        result = self._run(spark_session, bur_history_reassociation_df)
        rows = result.collect()
        assert len(rows) == 1
        row = rows[0]
        assert row["id_business_unit_region"] == 102
        assert row["id_region"] == 10
        assert row["id_business_unit"] == 20
        assert row["business_context"] == "RENT"
        assert row["sk_core_business_unit_region"] == _sha256_sk(
            "BUSINESS_UNIT_REGION", "102"
        )

    def test_stale_sibling_junction_dropped_for_pair(
        self, spark_session, bur_history_stale_sibling_df
    ):
        result = self._run(spark_session, bur_history_stale_sibling_df)
        rows = result.collect()
        assert len(rows) == 1
        row = rows[0]
        assert row["id_business_unit_region"] == 7214
        assert row["id_region"] == 2
        assert row["id_business_unit"] == 138
        assert row["business_context"] == "RENT"
        assert row["sk_core_business_unit_region"] == _sha256_sk(
            "BUSINESS_UNIT_REGION", "7214"
        )

    def test_pair_dedup_prefers_live_junction_over_higher_deleted_id(
        self, spark_session, bur_history_deleted_sibling_df
    ):
        result = self._run(spark_session, bur_history_deleted_sibling_df)
        rows = result.collect()
        assert len(rows) == 1
        row = rows[0]
        assert row["id_business_unit_region"] == 200, (
            "The live junction must win the pair even with a lower junction id"
        )
        assert row["is_deleted"] is False
        assert row["business_context"] == "SALE"

    def test_pair_dedup_ties_unobserved_junction_with_live_sibling(
        self, spark_session, bur_history_unobserved_sibling_df
    ):
        """A null is_deleted is live, so it must not outrank a live sibling with a higher id."""
        result = self._run(spark_session, bur_history_unobserved_sibling_df)
        rows = result.collect()
        assert len(rows) == 1
        row = rows[0]
        assert row["id_business_unit_region"] == 600, (
            "The highest live junction id must win when neither junction is deleted"
        )
        assert row["business_context"] == "RENT"
        assert row["sk_core_business_unit_region"] == _sha256_sk(
            "BUSINESS_UNIT_REGION", "600"
        )

    def test_fully_deleted_pair_is_flagged_for_deletion(
        self, spark_session, bur_history_deleted_pair_df
    ):
        """The row stays on the source carrying the flag; the merge does the deleting."""
        result = self._run(spark_session, bur_history_deleted_pair_df)
        rows = result.collect()
        assert len(rows) == 1
        assert rows[0]["id_business_unit_region"] == 400
        assert rows[0]["is_deleted"] is True


# ---------------------------------------------------------------------------
# run_pipeline — merge wiring
# ---------------------------------------------------------------------------


class TestRunPipelineMergeWiring:
    def _make_pipeline_args(self, table_name):
        return SimpleNamespace(
            table_name=table_name,
            load_start_date=None,
            load_end_date=None,
            partitions="['year', 'month', 'day']",
            schema="core_region",
            bucket="test-bucket",
            target_database_name=None,
            target_table_name=None,
        )

    def _run(self, spark_session, dataframe, table_name, config_map):
        job = CoreBusinessUnitSparkJob()
        args = self._make_pipeline_args(table_name)
        with (
            patch.object(
                CoreBusinessUnitSparkJob,
                "get_config",
                side_effect=_config_side_effect(config_map),
            ),
            patch.object(spark_session, "table", return_value=dataframe),
            patch(f"{_MODULE}.TablePrivileges"),
            patch(f"{_MODULE}.DataFrameDeltaTableLoaderPipeline") as mock_pipeline_cls,
        ):
            job.run_pipeline(dataframe, args, spark_session)
        return mock_pipeline_cls.call_args[1]

    def _bur_source(self, spark_session, bur_history_deleted_pair_df):
        job = CoreBusinessUnitSparkJob()
        args = _make_args("business_unit_region")
        with (
            patch.object(
                CoreBusinessUnitSparkJob,
                "get_config",
                side_effect=_config_side_effect(CONFIG_MAP_BUR),
            ),
            patch.object(
                spark_session, "table", return_value=bur_history_deleted_pair_df
            ),
        ):
            return job.create_core_model(spark_session, args)

    def test_control_column_excluded_from_both_merge_maps(
        self, spark_session, bur_history_deleted_pair_df
    ):
        """is_deleted must reach neither map, or schema auto-merge evolves it into the target."""
        source = self._bur_source(spark_session, bur_history_deleted_pair_df)
        kwargs = self._run(
            spark_session, source, "business_unit_region", CONFIG_MAP_BUR
        )

        assert "is_deleted" not in kwargs["when_matched_operation"]
        assert "is_deleted" not in kwargs["when_not_matched_operation"]
        assert set(kwargs["when_matched_operation"]) == PUBLISHED_BUR_COLUMNS
        assert set(kwargs["when_not_matched_operation"]) == PUBLISHED_BUR_COLUMNS

    def test_delete_and_insert_conditions_are_passed_through(
        self, spark_session, bur_history_deleted_pair_df
    ):
        source = self._bur_source(spark_session, bur_history_deleted_pair_df)
        kwargs = self._run(
            spark_session, source, "business_unit_region", CONFIG_MAP_BUR
        )

        assert kwargs["when_matched_delete_condition"] == "source.is_deleted = true"
        assert kwargs["when_not_matched_insert_condition"] == (
            "source.is_deleted IS NULL OR source.is_deleted = false"
        )

    def test_business_unit_keeps_insert_all_and_no_delete_clause(
        self, spark_session, bu_history_df
    ):
        """business_unit has no control column, so its merge behaviour is unchanged."""
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
            source = job.create_core_model(spark_session, args)

        kwargs = self._run(spark_session, source, "business_unit", CONFIG_MAP_BU)

        assert kwargs["when_not_matched_operation"] is None
        assert kwargs["when_matched_delete_condition"] is None
        assert kwargs["when_not_matched_insert_condition"] is None
        assert set(kwargs["when_matched_operation"]) == EXPECTED_BU_COLUMNS


# ---------------------------------------------------------------------------
# Unsupported table guard
# ---------------------------------------------------------------------------


class TestUnsupportedTable:
    def test_raises_value_error_for_unknown_table_name(self, spark_session):
        job = CoreBusinessUnitSparkJob()
        args = _make_args("nonexistent_table")
        with pytest.raises(ValueError, match="Unsupported table_name"):
            job.create_core_model(spark_session, args)
