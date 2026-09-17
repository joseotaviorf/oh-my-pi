"""Unit tests for ``load_agent_visit_funnel`` config-driven aggregations.

Run::

    uv run --directory packages/bietlejuice-runtime pytest \\
        test/dags/agents/dw_agent_visit_funnel/spark_jobs/test_load_agent_visit_funnel.py -q
"""

import importlib
import os
import sys
from datetime import date, datetime
from unittest.mock import MagicMock, patch

import pytest
from pyspark.sql import Row
from pyspark.sql.types import (
    DateType,
    DoubleType,
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)


def _repo_root() -> str:
    cur = os.path.abspath(os.path.dirname(__file__))
    while cur != os.path.dirname(cur):
        if os.path.exists(os.path.join(cur, ".git")):
            return cur
        cur = os.path.dirname(cur)
    raise RuntimeError("Cannot find repo root")


_SPARK_JOBS = os.path.join(
    _repo_root(), "dags", "agents", "dw_agent_visit_funnel", "spark_jobs"
)
if _SPARK_JOBS not in sys.path:
    sys.path.insert(0, _SPARK_JOBS)

_MODULE_PATH = "dags.agents.dw_agent_visit_funnel.spark_jobs.load_agent_visit_funnel"

_IMPORT_TIME_MOCKS = {
    "bietlejuice": MagicMock(),
    "bietlejuice.base": MagicMock(),
    "bietlejuice.base.validation": MagicMock(),
    "bietlejuice.base.validation.spark_args": MagicMock(),
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


VISIT_SCHEMA = StructType(
    [
        StructField("uuid_person_last_associated_agent", StringType(), True),
        StructField("uuid_person_agent_vbba", StringType(), True),
        StructField("dt_visit_created", DateType(), True),
        StructField("is_visit_booked", IntegerType(), True),
        StructField("nbr_reschedule", IntegerType(), True),
        StructField("is_visit_canceled", IntegerType(), True),
        StructField("is_visit_completed", IntegerType(), True),
        StructField("is_visit_unsuccessful", IntegerType(), True),
        StructField("is_visit_stalled", IntegerType(), True),
        StructField("is_visit_not_finished", IntegerType(), True),
        StructField("is_offer_submitted", IntegerType(), True),
        StructField("is_offer_accepted", IntegerType(), True),
        StructField("is_agreement_signed", IntegerType(), True),
        StructField("is_pfa_visit", IntegerType(), True),
        StructField("is_crcc_visit", IntegerType(), True),
        StructField("is_vbba_visit", IntegerType(), True),
        StructField("ts_visit_created", TimestampType(), True),
        StructField("ts_visit_done", TimestampType(), True),
        StructField("ts_offer_submitted", TimestampType(), True),
    ]
)

FACT_AGENT_SCHEMA = StructType(
    [
        StructField("uuid_person", StringType(), True),
        StructField("dt_ref", DateType(), True),
    ]
)


def _visit_row(**overrides):
    base = {
        "uuid_person_last_associated_agent": "person-overall",
        "uuid_person_agent_vbba": "person-vbba",
        "dt_visit_created": date(2026, 8, 1),
        "is_visit_booked": 1,
        "nbr_reschedule": 2,
        "is_visit_canceled": 0,
        "is_visit_completed": 1,
        "is_visit_unsuccessful": 0,
        "is_visit_stalled": 0,
        "is_visit_not_finished": 0,
        "is_offer_submitted": 1,
        "is_offer_accepted": 0,
        "is_agreement_signed": 0,
        "is_pfa_visit": 1,
        "is_crcc_visit": 0,
        "is_vbba_visit": 1,
        "ts_visit_created": datetime(2026, 8, 1, 10, 0, 0),
        "ts_visit_done": datetime(2026, 8, 2, 10, 0, 0),
        "ts_offer_submitted": datetime(2026, 8, 2, 22, 0, 0),
    }
    base.update(overrides)
    return Row(**base)


def test_metric_output_columns_follows_config_order():
    columns = _job.metric_output_columns()
    assert columns[0] == "total_visit"
    assert "total_visit_pfa" in columns
    assert "total_visit_vbba" in columns
    assert len(columns) == len(_job.METRIC_DEFINITIONS) * len(
        _job.DIMENSION_DEFINITIONS
    )


def test_build_metric_agg_expr_applies_dimension_slice(spark):
    visits_df = spark.createDataFrame(
        [
            Row(
                is_visit_booked=1,
                is_pfa_visit=0,
            ),
            Row(
                is_visit_booked=1,
                is_pfa_visit=1,
            ),
        ],
        schema=StructType(
            [
                StructField("is_visit_booked", IntegerType(), True),
                StructField("is_pfa_visit", IntegerType(), True),
            ]
        ),
    )
    metric = _job.MetricDefinition.sum_column("total_visit", "is_visit_booked")
    dimension = _job.DimensionDefinition(
        dimension_id="pfa",
        suffix="_pfa",
        person_column="uuid_person_last_associated_agent",
        slice=_job.DimensionDefinition.slice_when_flag("is_pfa_visit"),
    )
    result = visits_df.agg(_job.build_metric_agg_expr(metric, dimension)).collect()[0][
        0
    ]
    assert result == 1


def test_output_schema_matches_metric_config():
    schema = _job.output_schema()
    assert schema["total_visit"].dataType == LongType()
    assert schema["total_visit_pfa"].dataType == LongType()
    assert schema["total_visit_vbba"].dataType == LongType()
    assert schema["avg_hours_booked_to_completed"].dataType == DoubleType()
    assert schema["avg_hours_completed_to_offer_submitted_pfa"].dataType == DoubleType()
    assert schema["date_ref"].dataType == DateType()


def test_build_agent_visit_funnel_aggregates_all_cuts(spark):
    visits_df = spark.createDataFrame(
        [
            _visit_row(),
            _visit_row(
                uuid_person_last_associated_agent="person-overall",
                uuid_person_agent_vbba="person-vbba",
                is_pfa_visit=0,
                is_vbba_visit=0,
                is_visit_completed=0,
                is_offer_submitted=0,
                ts_visit_done=None,
                ts_offer_submitted=None,
            ),
        ],
        schema=VISIT_SCHEMA,
    )
    fact_df = spark.createDataFrame(
        [
            Row(uuid_person="person-overall", dt_ref=date(2026, 8, 1)),
            Row(uuid_person="person-inactive", dt_ref=date(2026, 8, 2)),
            Row(uuid_person="person-vbba", dt_ref=date(2026, 8, 1)),
        ],
        schema=FACT_AGENT_SCHEMA,
    )

    def _table(name: str):
        if name == _job.VISIT_FUNNEL_EVENT_TABLE:
            return visits_df
        if name == _job.FACT_AGENT_DAILY_TABLE:
            return fact_df
        raise AssertionError(f"unexpected table {name}")

    spark.table = _table  # type: ignore[method-assign]

    result = _job.build_agent_visit_funnel(
        spark,
        reprocess_start_date="2026-08-01",
        load_start_date="2026-08-01",
        load_end_date="2026-08-31",
    ).collect()

    by_person = {row.uuid_person: row for row in result}
    assert len(by_person) == 3

    overall = by_person["person-overall"]
    assert overall.total_visit == 2
    assert overall.total_visit_completed == 1
    assert overall.total_visit_pfa == 1
    assert overall.total_visit_crcc == 0
    assert overall.total_visit_vbba == 0
    assert overall.total_reschedule == 4
    assert overall.avg_hours_booked_to_completed == 24.0
    assert overall.avg_hours_completed_to_offer_submitted == 12.0
    assert overall.avg_hours_booked_to_completed_pfa == 24.0

    vbba = by_person["person-vbba"]
    assert vbba.total_visit_vbba == 1
    assert vbba.total_visit == 0

    inactive = by_person["person-inactive"]
    assert inactive.total_visit == 0
    assert inactive.total_offer_submitted == 0
    assert inactive.avg_hours_booked_to_completed is None


def test_resolve_delta_write_mode_merge():
    assert _job.resolve_delta_write_mode("merge") == _job.MERGE_KEYS


def test_resolve_delta_write_mode_batch_and_aliases():
    assert _job.resolve_delta_write_mode("batch") is None
    assert _job.resolve_delta_write_mode("overwrite_partitions") is None
    assert _job.resolve_delta_write_mode("overwrite") is None


def test_resolve_delta_write_mode_rejects_unknown():
    with pytest.raises(ValueError, match="Unsupported write_mode"):
        _job.resolve_delta_write_mode("truncate")


def test_validate_before_write_returns_none_on_empty(spark):
    empty = spark.createDataFrame([], _job.output_schema())
    assert _job.validate_before_write(empty) is None
