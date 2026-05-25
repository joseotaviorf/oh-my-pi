"""Unit tests for ``load_agent_new_agent_activation_metrics``.

We only lock:
  • per-reference_month new-broker predicate + persona exclusion (where backfill regressions lurk),
  • one full build wiring check (activated / not activated + PPA-null path + INDEPENDENT vs FR_FS),
  • empty output when Demand ``ts_created`` fails the cohort (join + filter).

Run::

    pytest packages/bietlejuice-runtime/test/dags/agents/enrich_agent_reports/spark_jobs/test_load_agent_new_agent_activation_metrics.py -q
"""

import importlib
from argparse import Namespace
from contextlib import ExitStack
from datetime import date, datetime
from unittest.mock import MagicMock, patch

import pytest
from pyspark.sql.functions import col
from pyspark.sql.types import (
    BooleanType,
    DateType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

_MODULE_PATH = (
    "dags.agents.enrich_agent_reports.spark_jobs"
    ".load_agent_new_agent_activation_metrics"
)

_IMPORT_TIME_MOCKS = {
    "bietlejuice": MagicMock(),
    "bietlejuice.base": MagicMock(),
    "bietlejuice.base.db": MagicMock(),
    "bietlejuice.base.databricks": MagicMock(),
    "bietlejuice.base.databricks.table_privileges": MagicMock(),
    "bietlejuice.base.spark": MagicMock(),
    "bietlejuice.base.spark.base_spark": MagicMock(),
    "bietlejuice.base.spark.unity_catalog_helper": MagicMock(),
    "bietlejuice.clients": MagicMock(),
    "bietlejuice.clients.db_clients": MagicMock(),
    "bietlejuice.loaders": MagicMock(),
    "bietlejuice.loaders.delta_loader": MagicMock(),
    "bietlejuice.services": MagicMock(),
    "bietlejuice.services.metastore_services": MagicMock(),
    "quintoandar_logger": MagicMock(),
}

with patch.dict("sys.modules", _IMPORT_TIME_MOCKS):
    _job = importlib.import_module(_MODULE_PATH)

_AGENT_SOURCE_SCHEMA = StructType(
    [
        StructField("id", LongType(), True),
        StructField("ts_created", TimestampType(), True),
        StructField("agent_type", StringType(), True),
    ]
)

_REF_TS_SCHEMA = StructType(
    [
        StructField("reference_month", DateType(), True),
        StructField("ts_created", TimestampType(), True),
    ]
)

_METRICS_INPUT_SCHEMA = StructType(
    [
        StructField("id_agent", LongType(), True),
        StructField("id_user", LongType(), True),
        StructField("reference_month", DateType(), True),
        StructField("total_listings_count", LongType(), True),
        StructField("total_tqc_count", LongType(), True),
        StructField("agent_status", StringType(), True),
        StructField("is_passive_lead_receiver", BooleanType(), True),
        StructField("ts_first_activation_tqc_referral", TimestampType(), True),
        StructField("ts_valid_activation_first_listing", TimestampType(), True),
    ]
)

_REF_MARCH = date(2025, 3, 1)


@pytest.mark.parametrize(
    "ts_created,expected_kept",
    [
        (datetime(2025, 2, 15, 12, 0, 0), True),
        (datetime(2024, 11, 1, 0, 0, 0), False),  # older than NEW_AGENT_MAX_DAYS window
        (datetime(2025, 4, 1, 0, 0, 0), False),  # after reference month-end
    ],
    ids=["inside_window", "too_old_for_month", "after_month_end"],
)
def test_new_broker_predicate_rows(spark, ts_created, expected_kept):
    df = spark.createDataFrame([(_REF_MARCH, ts_created)], _REF_TS_SCHEMA)
    filt = df.filter(
        _job._new_broker_within_reference_month(
            col("reference_month"), col("ts_created")
        )
    )
    assert filt.count() == (1 if expected_kept else 0)


def test_excluded_personas_never_enter_broker_profiles(spark):
    rows = [
        (i, datetime(2025, 2, 1, 0, 0, 0), t)
        for i, t in enumerate(_job.EXCLUDED_AGENT_TYPES, start=1)
    ]
    agents_df = spark.createDataFrame(rows, _AGENT_SOURCE_SCHEMA)
    mock_spark = MagicMock()
    mock_spark.table.return_value = agents_df
    _job.spark = mock_spark
    assert _job._eligible_broker_agent_profiles_df().count() == 0


def _make_build(spark, metrics_rows, broker_ts_created=None):
    if broker_ts_created is None:
        broker_ts_created = datetime(2025, 1, 15, 0, 0, 0)

    metrics_df = spark.createDataFrame(metrics_rows, _METRICS_INPUT_SCHEMA)
    status_schema = StructType(
        [
            StructField("id_user", LongType(), True),
            StructField("id_agent", LongType(), True),
            StructField("reference_month", DateType(), True),
            StructField("agent_status", StringType(), True),
            StructField("ciq_status", StringType(), True),
            StructField("is_passive_lead_receiver", BooleanType(), True),
            StructField("agent_status_start", TimestampType(), True),
        ]
    )
    status_rows = [
        (r[1], r[0], r[2], r[5], "ACTIVE", r[6], datetime(2025, 1, 1))
        for r in metrics_rows
    ]
    status_df = spark.createDataFrame(status_rows, status_schema)

    agent_data_df = spark.createDataFrame(
        [(r[0], broker_ts_created, "REGULAR") for r in metrics_rows],
        StructType(
            [
                StructField("id", LongType(), True),
                StructField("ts_created", TimestampType(), True),
                StructField("agent_type", StringType(), True),
            ]
        ),
    )
    partner_df = spark.createDataFrame(
        [(r[1], datetime(2025, 1, 1)) for r in metrics_rows],
        StructType(
            [
                StructField("id_user", LongType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        ),
    )
    empty_ppa = spark.createDataFrame(
        [],
        StructType(
            [
                StructField("id_agent", LongType(), True),
                StructField("reference_month", DateType(), True),
                StructField("total_ppa_count", LongType(), False),
                StructField("ts_first_ppa_activation", TimestampType(), True),
            ]
        ),
    )
    empty_city = spark.createDataFrame(
        [],
        StructType(
            [
                StructField("id_agent", LongType(), True),
                StructField("name_city", StringType(), True),
            ]
        ),
    )
    empty_da = spark.createDataFrame(
        [],
        StructType(
            [
                StructField("id_agent", LongType(), True),
                StructField("is_sale_agent", BooleanType(), True),
                StructField("is_rent_agent", BooleanType(), True),
            ]
        ),
    )

    args = Namespace(
        env="forno",
        datalake_bucket="5a-datalake-prod",
        database_base_name="agent_reports",
        dag_name="enrich_agent_reports",
        table_name="agent_new_agent_activation_metrics",
        load_end_date="2025-01-31",
        months_window=1,
        run_mode="dev",
    )

    def _table_side_effect(table_name):
        if table_name == _job.TABLE_STATUS_BY_MONTH:
            return status_df
        if table_name == _job.TABLE_AGENT_DATA:
            return agent_data_df
        if table_name == _job.TABLE_PARTNER_AGENT:
            return partner_df
        raise ValueError(table_name)

    mock_spark = MagicMock()
    mock_spark.table.side_effect = _table_side_effect
    _job.spark = mock_spark

    with ExitStack() as stack:
        stack.enter_context(
            patch.object(_job, "_tqc_first_date_df", return_value=metrics_df)
        )
        stack.enter_context(
            patch.object(_job, "_valid_first_listing_df", return_value=metrics_df)
        )
        stack.enter_context(
            patch.object(_job, "_ppa_visits_df", return_value=empty_ppa)
        )
        stack.enter_context(
            patch.object(_job, "_agent_city_df", return_value=empty_city)
        )
        stack.enter_context(
            patch.object(_job, "_dim_agent_business_context_df", return_value=empty_da)
        )
        return _job.build_agent_new_agent_activation_metrics(args)


def test_build_integration_activation_segment_and_barren_ppa(spark):
    """FL/TQC OR → ``is_activated``; mocked-empty PPA → zero PPA cols; passive → FR_FS."""

    def rw(i, listings, tqc, passive=False):
        return (
            i,
            10 + i,
            date(2025, 1, 1),
            listings,
            tqc,
            "ACTIVE",
            passive,
            None,
            None,
        )

    df = _make_build(
        spark,
        [
            rw(1, 0, 0, False),
            rw(2, 1, 0, False),
            rw(3, 0, 1, False),
            rw(4, 0, 0, True),
        ],
    )
    out = {r.id_agent: r for r in df.collect()}

    assert out[1].is_activated is False
    assert out[2].is_activated is True
    assert out[3].is_activated is True
    assert out[1].is_ppa_active_in_month is False and out[1].total_ppa_count == 0

    assert out[2].agent_type_segment == "INDEPENDENT"
    assert out[4].agent_type_segment == "FR_FS"
    assert all(r.agent_business_context == "UNKNOWN" for r in out.values())


def test_is_channel_active_rollups_prior_reference_month(spark):
    """``is_*_active_in_month`` includes activity in ``reference_month - 1``; ``total_*`` stays current."""
    metrics_rows = [
        (1, 11, date(2024, 12, 1), 1, 1, "ACTIVE", False, None, None),
        (1, 11, date(2025, 1, 1), 0, 0, "ACTIVE", False, None, None),
    ]
    metrics_df = spark.createDataFrame(metrics_rows, _METRICS_INPUT_SCHEMA)
    status_schema = StructType(
        [
            StructField("id_user", LongType(), True),
            StructField("id_agent", LongType(), True),
            StructField("reference_month", DateType(), True),
            StructField("agent_status", StringType(), True),
            StructField("ciq_status", StringType(), True),
            StructField("is_passive_lead_receiver", BooleanType(), True),
            StructField("agent_status_start", TimestampType(), True),
        ]
    )
    status_df = spark.createDataFrame(
        [(11, 1, date(2025, 1, 1), "ACTIVE", "ACTIVE", False, datetime(2025, 1, 1))],
        status_schema,
    )
    agent_data_df = spark.createDataFrame(
        [(1, datetime(2025, 1, 15, 0, 0, 0), "REGULAR")],
        StructType(
            [
                StructField("id", LongType(), True),
                StructField("ts_created", TimestampType(), True),
                StructField("agent_type", StringType(), True),
            ]
        ),
    )
    partner_df = spark.createDataFrame(
        [(11, datetime(2025, 1, 1))],
        StructType(
            [
                StructField("id_user", LongType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        ),
    )
    empty_ppa = spark.createDataFrame(
        [],
        StructType(
            [
                StructField("id_agent", LongType(), True),
                StructField("reference_month", DateType(), True),
                StructField("total_ppa_count", LongType(), False),
                StructField("ts_first_ppa_activation", TimestampType(), True),
            ]
        ),
    )
    empty_city = spark.createDataFrame(
        [],
        StructType(
            [
                StructField("id_agent", LongType(), True),
                StructField("name_city", StringType(), True),
            ]
        ),
    )
    empty_da = spark.createDataFrame(
        [],
        StructType(
            [
                StructField("id_agent", LongType(), True),
                StructField("is_sale_agent", BooleanType(), True),
                StructField("is_rent_agent", BooleanType(), True),
            ]
        ),
    )
    args = Namespace(
        env="forno",
        datalake_bucket="5a-datalake-prod",
        database_base_name="agent_reports",
        dag_name="enrich_agent_reports",
        table_name="agent_new_agent_activation_metrics",
        load_end_date="2025-01-31",
        months_window=1,
        run_mode="dev",
    )

    def _table_side_effect(table_name):
        if table_name == _job.TABLE_STATUS_BY_MONTH:
            return status_df
        if table_name == _job.TABLE_AGENT_DATA:
            return agent_data_df
        if table_name == _job.TABLE_PARTNER_AGENT:
            return partner_df
        raise ValueError(table_name)

    mock_spark = MagicMock()
    mock_spark.table.side_effect = _table_side_effect
    _job.spark = mock_spark

    with ExitStack() as stack:
        stack.enter_context(
            patch.object(_job, "_tqc_first_date_df", return_value=metrics_df)
        )
        stack.enter_context(
            patch.object(_job, "_valid_first_listing_df", return_value=metrics_df)
        )
        stack.enter_context(
            patch.object(_job, "_ppa_visits_df", return_value=empty_ppa)
        )
        stack.enter_context(
            patch.object(_job, "_agent_city_df", return_value=empty_city)
        )
        stack.enter_context(
            patch.object(_job, "_dim_agent_business_context_df", return_value=empty_da)
        )
        row_out = _job.build_agent_new_agent_activation_metrics(args).collect()[0]

    assert row_out.reference_month == date(2025, 1, 1)
    assert row_out.total_listings_count == 0 and row_out.total_tqc_count == 0
    assert (
        row_out.is_ciq_active_in_month is True
        and row_out.is_tqc_active_in_month is True
    )
    assert row_out.is_activated is True


def test_agent_business_context_from_clean_layer(spark):
    """Flags from mocked ``_dim_agent_business_context_df`` map to string context."""
    row = (1, 11, date(2025, 1, 1), 0, 0, "ACTIVE", False, None, None)
    metrics_df = spark.createDataFrame([row], _METRICS_INPUT_SCHEMA)
    status_schema = StructType(
        [
            StructField("id_user", LongType(), True),
            StructField("id_agent", LongType(), True),
            StructField("reference_month", DateType(), True),
            StructField("agent_status", StringType(), True),
            StructField("ciq_status", StringType(), True),
            StructField("is_passive_lead_receiver", BooleanType(), True),
            StructField("agent_status_start", TimestampType(), True),
        ]
    )
    status_df = spark.createDataFrame(
        [(11, 1, date(2025, 1, 1), "ACTIVE", "ACTIVE", False, datetime(2025, 1, 1))],
        status_schema,
    )
    agent_data_df = spark.createDataFrame(
        [(1, datetime(2025, 1, 15, 0, 0, 0), "REGULAR")],
        StructType(
            [
                StructField("id", LongType(), True),
                StructField("ts_created", TimestampType(), True),
                StructField("agent_type", StringType(), True),
            ]
        ),
    )
    partner_df = spark.createDataFrame(
        [(11, datetime(2025, 1, 1))],
        StructType(
            [
                StructField("id_user", LongType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        ),
    )
    empty_ppa = spark.createDataFrame(
        [],
        StructType(
            [
                StructField("id_agent", LongType(), True),
                StructField("reference_month", DateType(), True),
                StructField("total_ppa_count", LongType(), False),
                StructField("ts_first_ppa_activation", TimestampType(), True),
            ]
        ),
    )
    empty_city = spark.createDataFrame(
        [],
        StructType(
            [
                StructField("id_agent", LongType(), True),
                StructField("name_city", StringType(), True),
            ]
        ),
    )
    da_df = spark.createDataFrame(
        [(1, True, True)],
        StructType(
            [
                StructField("id_agent", LongType(), True),
                StructField("is_sale_agent", BooleanType(), True),
                StructField("is_rent_agent", BooleanType(), True),
            ]
        ),
    )
    args = Namespace(
        env="forno",
        datalake_bucket="5a-datalake-prod",
        database_base_name="agent_reports",
        dag_name="enrich_agent_reports",
        table_name="agent_new_agent_activation_metrics",
        load_end_date="2025-01-31",
        months_window=1,
        run_mode="dev",
    )

    def _table_side_effect(table_name):
        if table_name == _job.TABLE_STATUS_BY_MONTH:
            return status_df
        if table_name == _job.TABLE_AGENT_DATA:
            return agent_data_df
        if table_name == _job.TABLE_PARTNER_AGENT:
            return partner_df
        raise ValueError(table_name)

    mock_spark = MagicMock()
    mock_spark.table.side_effect = _table_side_effect
    _job.spark = mock_spark

    with ExitStack() as stack:
        stack.enter_context(
            patch.object(_job, "_tqc_first_date_df", return_value=metrics_df)
        )
        stack.enter_context(
            patch.object(_job, "_valid_first_listing_df", return_value=metrics_df)
        )
        stack.enter_context(
            patch.object(_job, "_ppa_visits_df", return_value=empty_ppa)
        )
        stack.enter_context(
            patch.object(_job, "_agent_city_df", return_value=empty_city)
        )
        stack.enter_context(
            patch.object(_job, "_dim_agent_business_context_df", return_value=da_df)
        )
        one = _job.build_agent_new_agent_activation_metrics(args).collect()[0]
    assert one.agent_business_context == "FOR_SALE_AND_FOR_RENT"


def test_build_includes_row_when_independent_registration_in_window_even_if_demand_old(
    spark,
):
    """Demand ts_created too old but dt_independent_agent_registered (agent_status_start)
    falls within NEW_AGENT_MAX_DAYS → row included via OR filter."""
    row = (1, 10, date(2025, 1, 1), 1, 1, "ACTIVE", False, None, None)
    # agent_status_start = 2025-01-01 (built in _make_build); 2020 demand is old but independent is new
    assert (
        _make_build(
            spark, [row], broker_ts_created=datetime(2020, 6, 1, 0, 0, 0)
        ).count()
        == 1
    )


def test_build_yields_empty_when_both_demand_and_independent_outside_cohort(spark):
    """Both Demand ts_created and dt_independent_agent_registered are older than NEW_AGENT_MAX_DAYS."""
    row = (1, 10, date(2025, 1, 1), 1, 1, "ACTIVE", True, None, None)
    # is_passive_lead_receiver=True → never enters last_independent → dt_independent_agent_registered=null
    # broker_ts_created=2020 → demand check fails; null independent → OR is False
    assert (
        _make_build(
            spark, [row], broker_ts_created=datetime(2020, 6, 1, 0, 0, 0)
        ).count()
        == 0
    )
