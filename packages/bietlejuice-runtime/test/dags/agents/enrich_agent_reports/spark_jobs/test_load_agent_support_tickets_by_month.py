"""Regressions for ``_add_eligibility_flags`` in ``load_agent_support_tickets_by_month``.

Whole-job wiring (listings joins, Zendesk ingest) belongs on Forno/Databricks — not here.

We keep **five business rules that have already churned**: passive-based FR/FS active,
independent ∩ three-way AND, CIQ-active listing strictly above the floor,
Demand eligible, dual inactive ineligible. Collapsed into **three tests** instead of dozens
of parametrized permutations — same predicates, fewer collection cycles.

::

    pytest packages/bietlejuice-runtime/test/dags/agents/enrich_agent_reports/spark_jobs/test_load_agent_support_tickets_by_month.py -q
"""

import importlib
from datetime import date
from unittest.mock import MagicMock, patch

from pyspark.sql.types import (
    ArrayType,
    BooleanType,
    DateType,
    LongType,
    StringType,
    StructField,
    StructType,
)

_MODULE_PATH = (
    "dags.agents.enrich_agent_reports.spark_jobs.load_agent_support_tickets_by_month"
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

_add_eligibility_flags = _job._add_eligibility_flags
_MIN_L = _job.MIN_LISTINGS_FOR_ACTIVE_CIQ

_INPUT_SCHEMA = StructType(
    [
        StructField("id_user", LongType(), True),
        StructField("id_agent", LongType(), True),
        StructField("reference_month", DateType(), True),
        StructField("total_listings_count", LongType(), True),
        StructField("total_visits_count", LongType(), True),
        StructField("is_ciq_qualified_active", BooleanType(), True),
        StructField("is_passive_lead_receiver_current", BooleanType(), True),
        StructField("is_sale_agent", BooleanType(), True),
        StructField("is_rent_agent", BooleanType(), True),
        StructField("agent_status", StringType(), True),
        StructField("ciq_status", StringType(), True),
        StructField("total_tickets", LongType(), True),
        StructField("sum_reopens", LongType(), True),
        StructField("ticket_breakdown_aggregated", ArrayType(StringType()), True),
    ]
)


def _row(
    id_u,
    *,
    agent_status=None,
    ciq_status="INACTIVE",
    passive=None,
    listings=0,
):
    return (
        id_u,
        100 + id_u,
        date(2025, 1, 1),
        listings,
        0,
        False,
        passive,
        None,
        None,
        agent_status,
        ciq_status,
        None,
        None,
        None,
    )


def test_passive_receiver_fr_fs_active_column(spark):
    """Passive + Demand ACTIVE ⇒ ``is_agent_active``; INDEPENDENT branch must fail that flag."""
    rows = spark.createDataFrame(
        [
            _row(1, passive=True, agent_status="ACTIVE"),
            _row(2, passive=False, agent_status="ACTIVE"),
            _row(3, passive=None, agent_status="ACTIVE"),
        ],
        _INPUT_SCHEMA,
    )
    out = {r.id_user: r for r in _add_eligibility_flags(rows).collect()}
    assert out[1].is_agent_active and out[3].is_agent_active
    assert out[2].is_agent_active is False


def test_independent_conjunct_demarcation_rows(spark):
    """Triple-AND for independent; ``is_ineligible`` only when both statuses INACTIVE."""
    rows = spark.createDataFrame(
        [
            _row(10, passive=False, agent_status="ACTIVE", ciq_status="ACTIVE"),
            _row(11, passive=True, agent_status="ACTIVE", ciq_status="ACTIVE"),
            _row(12, passive=False, agent_status="ACTIVE", ciq_status="INACTIVE"),
            _row(20, passive=False, agent_status="INACTIVE", ciq_status="INACTIVE"),
            _row(21, passive=False, agent_status="INACTIVE", ciq_status="ACTIVE"),
        ],
        _INPUT_SCHEMA,
    )
    x = {r.id_user: r for r in _add_eligibility_flags(rows).collect()}

    assert x[10].is_independent_agent and x[10].is_ineligible is False

    assert x[11].is_independent_agent is False
    assert x[12].is_independent_agent is False

    assert x[20].is_ineligible and x[20].is_independent_agent is False

    assert x[21].is_ineligible is False


def test_ciq_activity_listing_floor_and_demand_gate(spark):
    """``is_ciq_active`` requires ``> MIN`` not ``≥``; ``is_demand_agent_eligible`` is ACTIVE-only."""
    rows = spark.createDataFrame(
        [
            _row(30, ciq_status="ACTIVE", listings=_MIN_L + 1),
            _row(31, ciq_status="ACTIVE", listings=_MIN_L),
            _row(32, agent_status=None),
            _row(33, agent_status="ACTIVE"),
        ],
        _INPUT_SCHEMA,
    )
    z = {r.id_user: r for r in _add_eligibility_flags(rows).collect()}

    assert z[30].is_ciq_active and z[31].is_ciq_active is False

    assert z[32].is_demand_agent_eligible is False
    assert z[33].is_demand_agent_eligible
