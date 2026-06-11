# Databricks notebook source
# DBTITLE 1,Local dev configuration
# MAGIC %run "/Workspace/Data Engineering/Data Partners/1. Utils/templates/local_config"

# COMMAND ----------
#
# load_agent_new_agent_activation_metrics — ETL summary
# ---------------------------------------------------------------------------
# Chore: no-op comment to trigger Woodpecker upload-dag-packages-spark-jobs-s3-prod on merge.
# Writes: enrich schema table agent_new_agent_activation_metrics (Delta, merge on id_user +
# reference_month, partition reference_month).
#
# Steps:
#   1. `_month_range`: inclusive month window from `load_end_date` + `months_window` (anchors are
#      first calendar day of first/last months in window).
#   2. Read `agent_status_by_month` in window; derive `dt_independent_agent_registered` from status.
#   3. Inner-join `agent_data`: exclude Vistoria / VistoriaQuarteirizada / SessaoFotos personas.
#   4. Left-join ``agent_data_business_contexts_served`` on ``id_agent`` → ``agent_business_context`` (For Sale / For Rent / both / unknown).
#   5. Per-row new-broker cohort: keep if Demand ``ts_created`` OR ``dt_independent_agent_registered``
#      is within NEW_AGENT_MAX_DAYS of ``last_day(reference_month)`` (evaluated per row).
#   6. Join activations — valid first listing (`ciq_first_listing`), TQC self-referral
#      (`offer_specialists`), PPA visits (`visit_schedules` × `preferred_property_agent_relation_history`),
#      optional `name_city` from region hierarchy (`region`, `agent_region_data`).
#   7. Derive activation and segment flags; ``is_*_active_in_month`` / ``is_activated`` use activity in
#      ``reference_month`` **or** the prior calendar month (single-month ``total_*_count`` unchanged).
#      Three ``days_since_*`` vs ``last_day(reference_month)``; ``validate_before_write`` then Delta load.
#
# How to run unit tests (repo root; use project pyenv env `bi-etl-ejuice`):
#   cd packages/bietlejuice-runtime && PYTHONPATH=src:../.. uv run --project envs/dbr-16-4 pytest test/dags/agents/enrich_agent_reports/spark_jobs/test_load_agent_new_agent_activation_metrics.py -v
#

# DBTITLE 1,Import libs
from __future__ import annotations

from argparse import ArgumentParser, Namespace
from datetime import date, datetime, timedelta
from typing import Optional

from dateutil.relativedelta import relativedelta
from pyspark.sql import Column, DataFrame, Window
from pyspark.sql.functions import (
    add_months,
    coalesce,
    col,
    count,
    countDistinct,
    date_trunc,
    datediff,
    last_day,
    lit,
    to_date,
    when,
)
from pyspark.sql.functions import (
    min as spark_min,
)
from pyspark.sql.types import (
    BooleanType,
    DateType,
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

# COMMAND ----------

# DBTITLE 1,Setup & Constants
JOB_NAME = "load_agent_new_agent_activation_metrics"
logger = QuintoAndarLogger(JOB_NAME)

MONTHS_WINDOW_DEFAULT = 2
NEW_AGENT_MAX_DAYS = 60

TABLE_STATUS_BY_MONTH = "datalake_agent_reports.agent_status_by_month"
TABLE_OFFER_SPECIALISTS = "datalake_sale_offer_flows.offer_specialists"
TABLE_CIQ_FIRST_LISTING = "datalake_tiers.ciq_first_listing"
TABLE_PARTNER_AGENT = "datalake_ebdb_clean.partner_agent"
TABLE_AGENT_DATA = "datalake_ebdb_clean.agent_data"
TABLE_VISIT_SCHEDULES = "datalake_visit.visit_schedules"
TABLE_PPA_HISTORY = "datalake_ebdb_agents.preferred_property_agent_relation_history"
TABLE_REGION = "datalake_ebdb_clean.region"
TABLE_AGENT_REGION_DATA = "datalake_ebdb_clean.agent_region_data"
TABLE_AGENT_BIZ_CTX = "datalake_ebdb_clean.agent_data_business_contexts_served"

EXCLUDED_AGENT_TYPES = ["Vistoria", "VistoriaQuarteirizada", "SessaoFotos"]
MAX_REGION_DEPTH = 10

# COMMAND ----------

# DBTITLE 1,Argument parsing
ARG_SPEC = [
    ("env", str, "forno", "Environment: forno/prod"),
    ("datalake_bucket", str, "5a-datalake-prod", "Datalake bucket"),
    ("database_base_name", str, "agent_reports", "Base name for database (schema)"),
    ("dag_name", str, "enrich_agent_reports", "DAG name"),
    (
        "table_name",
        str,
        "agent_new_agent_activation_metrics",
        "Target enrich table name",
    ),
    (
        "load_start_date",
        str,
        lambda: (date.today() - timedelta(days=30)).isoformat(),
        "Interval start (alignment with DAG; window uses load_end_date + months_window)",
    ),
    (
        "load_end_date",
        str,
        lambda: date.today().isoformat(),
        "Interval end YYYY-MM-DD (window end)",
    ),
    ("run_mode", str, "dev", "Run mode: prod/dev"),
    (
        "months_window",
        int,
        MONTHS_WINDOW_DEFAULT,
        "Number of months in the lookback window",
    ),
]


def _defaults():
    return [d() if callable(d) else d for _, _, d, _ in ARG_SPEC]


def parse_args() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    default_values = _defaults()
    for (name, type_, _default, help_text), default_val in zip(
        ARG_SPEC, default_values
    ):
        parser.add_argument(
            name, nargs="?", type=type_, default=default_val, help=help_text
        )
    add_validation_target_args(parser)
    namespace, _ = parser.parse_known_args()
    return namespace


# COMMAND ----------


# DBTITLE 1,Helper functions
def _month_range(load_end_date: str, months_window: int) -> tuple[date, date]:
    """Return (month_start, month_end) as Python dates for the lookback window."""
    end_date = datetime.strptime(load_end_date, "%Y-%m-%d").date()
    month_end = end_date.replace(day=1)
    month_start = month_end - relativedelta(months=months_window - 1)
    return month_start, month_end


def _agent_city_df() -> DataFrame:
    """Primary city name per agent.
    Walks each region's parent chain (up to MAX_REGION_DEPTH) to find the nearest
    ancestor with level == 'Cidade'. When an agent has multiple regions, takes the
    alphabetically first city to produce one row per agent.
    """
    region = spark.table(TABLE_REGION).select(
        col("id").alias("region_id"),
        col("id_parent_region"),
        col("name"),
        col("level"),
    )
    # Seed: start at the region itself, record city name if already at Cidade level.
    ancestor = region.select(
        col("region_id"),
        col("id_parent_region").alias("current_parent"),
        when(col("level") == "Cidade", col("name")).alias("name_city"),
    )
    parent = region.select(
        col("region_id").alias("p_id"),
        col("id_parent_region").alias("p_parent"),
        col("level").alias("p_level"),
        col("name").alias("p_name"),
    )
    for _ in range(MAX_REGION_DEPTH - 1):
        ancestor = ancestor.join(
            parent, col("current_parent") == col("p_id"), "left"
        ).select(
            col("region_id"),
            coalesce(col("p_parent"), col("current_parent")).alias("current_parent"),
            coalesce(
                col("name_city"),
                when(col("p_level") == "Cidade", col("p_name")),
            ).alias("name_city"),
        )
    return (
        spark.table(TABLE_AGENT_REGION_DATA)
        .join(ancestor, col("id_regions") == col("region_id"))
        .filter(col("name_city").isNotNull())
        .groupBy(col("id_agent_data").alias("id_agent"))
        .agg(spark_min("name_city").alias("name_city"))
    )


# COMMAND ----------


# DBTITLE 1,TQC first lead referral by user/month
def _tqc_first_date_df(month_start: date, month_end: date) -> DataFrame:
    """TQC (self-referral) count and first activation per (id_user, reference_month)."""
    return (
        spark.table(TABLE_OFFER_SPECIALISTS)
        .filter(col("id_user_agent_lead_referral") == col("id_user_agent"))
        .withColumn(
            "reference_month",
            to_date(date_trunc("month", col("ts_agent_lead_referral_updated"))),
        )
        .groupBy(col("id_user_agent").alias("id_user"), "reference_month")
        .agg(
            count("id_offer").alias("total_tqc_count"),
            spark_min("ts_agent_lead_referral_updated").alias(
                "ts_first_activation_tqc_referral"
            ),
        )
        .withColumn(
            "ts_first_activation_tqc_referral",
            spark_min("ts_first_activation_tqc_referral").over(
                Window.partitionBy("id_user")
            ),
        )
        .filter(
            (col("reference_month") >= lit(month_start))
            & (col("reference_month") <= lit(month_end))
        )
    )


# COMMAND ----------


# DBTITLE 1,Valid first listing by user/month
def _valid_first_listing_df(month_start: date, month_end: date) -> DataFrame:
    """Valid first listing count and first activation per (id_user, reference_month)."""
    return (
        spark.table(TABLE_CIQ_FIRST_LISTING)
        .filter(col("is_first_listing_valid") == True)
        .withColumn(
            "reference_month",
            to_date(date_trunc("month", col("ts_original_first_listing"))),
        )
        .groupBy("id_agent", "id_user", "reference_month")
        .agg(
            count("*").alias("total_listings_count"),
            spark_min("ts_original_first_listing").alias(
                "ts_valid_activation_first_listing"
            ),
        )
        .withColumn(
            "ts_valid_activation_first_listing",
            spark_min("ts_valid_activation_first_listing").over(
                Window.partitionBy("id_user")
            ),
        )
        .filter(
            (col("reference_month") >= lit(month_start))
            & (col("reference_month") <= lit(month_end))
        )
    )


# COMMAND ----------


# DBTITLE 1,New-broker cohort (row-level vs reference_month)
def _new_broker_within_reference_month(
    reference_month_col: Column, ts_created_col: Column
) -> Column:
    """True when ``ts_created_col`` is on or before ``last_day(reference_month)`` and within
    NEW_AGENT_MAX_DAYS of that date. Null ``ts_created_col`` evaluates to False.
    """
    month_end_dt = last_day(reference_month_col)
    d = datediff(month_end_dt, to_date(ts_created_col))
    return (d >= 0) & (d <= NEW_AGENT_MAX_DAYS)


def _eligible_broker_agent_profiles_df() -> DataFrame:
    """agent_data excluding vistoria/foto personas; paired with ``_new_broker_within_reference_month`` after status join."""
    return (
        spark.table(TABLE_AGENT_DATA)
        .filter(col("ts_created").isNotNull())
        .filter(~col("agent_type").isin(EXCLUDED_AGENT_TYPES))
        .select(
            col("id").alias("brk_id_agent"), col("ts_created").alias("brk_ts_created")
        )
    )


def _dim_agent_business_context_df() -> DataFrame:
    """For Sale / For Rent flags from ``agent_data_business_contexts_served`` (clean layer).

    Pivots one-row-per-context into per-agent boolean flags:
      is_sale_agent = has SALE or SALE_PRIMARY_MARKET context
      is_rent_agent = has RENT context
    """
    from pyspark.sql.functions import array_contains, collect_list

    ctx = (
        spark.table(TABLE_AGENT_BIZ_CTX)
        .groupBy(col("id_agent_data").alias("id_agent"))
        .agg(collect_list("business_context").alias("contexts"))
    )
    return ctx.select(
        col("id_agent"),
        (
            array_contains(col("contexts"), "SALE")
            | array_contains(col("contexts"), "SALE_PRIMARY_MARKET")
        ).alias("is_sale_agent"),
        array_contains(col("contexts"), "RENT").alias("is_rent_agent"),
    )


# COMMAND ----------


# DBTITLE 1,PPA visits by agent/month
def _ppa_visits_df(month_start: date, month_end: date) -> DataFrame:
    """PPA-origin completed visits per (id_agent, reference_month).
    A visit is PPA when the agent was the preferred property agent for the visited house at visit time.
    """
    ppa = spark.table(TABLE_PPA_HISTORY).select(
        col("id_related_agent").alias("ppa_id_agent"),
        col("id_house").alias("ppa_id_house"),
        col("ts_relation_started"),
        col("ts_relation_ended"),
    )
    dt_visit = to_date(col("ts_schedule_visit"))
    return (
        spark.table(TABLE_VISIT_SCHEDULES)
        .filter(col("is_completed") == True)
        .filter(col("ts_schedule_visit").isNotNull())
        .withColumn(
            "reference_month", to_date(date_trunc("month", col("ts_schedule_visit")))
        )
        .filter(
            (col("reference_month") >= lit(month_start))
            & (col("reference_month") <= lit(month_end))
        )
        .join(
            ppa,
            (col("id_agent") == col("ppa_id_agent"))
            & (col("id_house") == col("ppa_id_house"))
            & (dt_visit >= to_date(col("ts_relation_started")))
            & (
                col("ts_relation_ended").isNull()
                | (dt_visit <= to_date(col("ts_relation_ended")))
            ),
            "inner",
        )
        .groupBy("id_agent", "reference_month")
        .agg(
            countDistinct("id_schedule").alias("total_ppa_count"),
            spark_min(col("ts_schedule_visit")).alias("ts_first_ppa_activation"),
        )
    )


# COMMAND ----------


# DBTITLE 1,Main builder
def build_agent_new_agent_activation_metrics(args: Namespace) -> DataFrame:
    """Nationwide new-agent activation metrics: within 60 days of each row's ``reference_month`` month-end."""
    months_window = int(getattr(args, "months_window", MONTHS_WINDOW_DEFAULT))
    month_start, month_end = _month_range(args.load_end_date, months_window)
    # Pull one extra month before the status window so prior-month activity joins exist at window start.
    activity_month_start = month_start - relativedelta(months=1)

    status = spark.table(TABLE_STATUS_BY_MONTH).filter(
        (col("reference_month") >= lit(month_start))
        & (col("reference_month") <= lit(month_end))
    )
    _independent_window = (
        Window.partitionBy("id_agent")
        .orderBy("reference_month")
        .rowsBetween(Window.unboundedPreceding, 0)
    )
    last_independent = status.withColumn(
        "dt_independent_agent_registered",
        to_date(
            spark_min(
                when(
                    ~col("is_passive_lead_receiver") & (col("ciq_status") == "ACTIVE"),
                    col("agent_status_start"),
                )
            ).over(_independent_window)
        ),
    ).select(
        col("id_agent").alias("fi_id_agent"),
        col("reference_month").alias("fi_reference_month"),
        "dt_independent_agent_registered",
    )

    agent_type_segment = (
        when(
            (col("s.agent_status") == "ACTIVE")
            & ~col("s.is_passive_lead_receiver")
            & (col("s.ciq_status") == "ACTIVE"),
            lit("INDEPENDENT"),
        )
        .when(
            (col("s.agent_status") == "ACTIVE") & col("s.is_passive_lead_receiver"),
            lit("FR_FS"),
        )
        .when(
            (col("s.ciq_status") == "ACTIVE") & (col("s.agent_status") != "ACTIVE"),
            lit("CIQ_ONLY"),
        )
        .otherwise(lit("OTHER"))
    )
    tqc_by_month = _tqc_first_date_df(activity_month_start, month_end)
    vfl_by_month = _valid_first_listing_df(activity_month_start, month_end)
    ppa_by_month = _ppa_visits_df(activity_month_start, month_end)
    return (
        status.alias("s")
        .join(
            _dim_agent_business_context_df().alias("da"),
            col("s.id_agent") == col("da.id_agent"),
            "left",
        )
        .join(
            _eligible_broker_agent_profiles_df().alias("brk"),
            col("s.id_agent") == col("brk.brk_id_agent"),
            "inner",
        )
        .join(
            last_independent,
            (col("s.id_agent") == col("fi_id_agent"))
            & (col("s.reference_month") == col("fi_reference_month")),
            "left",
        )
        .filter(
            _new_broker_within_reference_month(
                col("s.reference_month"), col("brk.brk_ts_created")
            )
            | _new_broker_within_reference_month(
                col("s.reference_month"), col("dt_independent_agent_registered")
            )
        )
        .join(
            spark.table(TABLE_PARTNER_AGENT).select(
                col("id_user").alias("pa_id_user"),
                col("ts_created").alias("ts_ciq_created"),
            ),
            col("s.id_user") == col("pa_id_user"),
            "left",
        )
        .join(
            tqc_by_month.alias("tqc_curr"),
            (col("s.id_user") == col("tqc_curr.id_user"))
            & (col("s.reference_month") == col("tqc_curr.reference_month")),
            "left",
        )
        .join(
            tqc_by_month.alias("tqc_prev"),
            (col("s.id_user") == col("tqc_prev.id_user"))
            & (
                col("tqc_prev.reference_month")
                == add_months(col("s.reference_month"), -1)
            ),
            "left",
        )
        .join(
            vfl_by_month.alias("vfl_curr"),
            (col("s.id_user") == col("vfl_curr.id_user"))
            & (col("s.reference_month") == col("vfl_curr.reference_month")),
            "left",
        )
        .join(
            vfl_by_month.alias("vfl_prev"),
            (col("s.id_user") == col("vfl_prev.id_user"))
            & (
                col("vfl_prev.reference_month")
                == add_months(col("s.reference_month"), -1)
            ),
            "left",
        )
        .join(
            ppa_by_month.alias("ppa_curr"),
            (col("s.id_agent") == col("ppa_curr.id_agent"))
            & (col("s.reference_month") == col("ppa_curr.reference_month")),
            "left",
        )
        .join(
            ppa_by_month.alias("ppa_prev"),
            (col("s.id_agent") == col("ppa_prev.id_agent"))
            & (
                col("ppa_prev.reference_month")
                == add_months(col("s.reference_month"), -1)
            ),
            "left",
        )
        .join(
            _agent_city_df().alias("city"),
            col("s.id_agent") == col("city.id_agent"),
            "left",
        )
        .select(
            col("s.id_user"),
            col("s.id_agent"),
            col("s.reference_month"),
            col("s.ciq_status"),
            col("s.agent_status"),
            col("s.is_passive_lead_receiver"),
            col("dt_independent_agent_registered"),
            col("brk.brk_ts_created").alias("ts_agent_created"),
            col("ts_ciq_created"),
            col("tqc_curr.ts_first_activation_tqc_referral"),
            coalesce(col("tqc_curr.total_tqc_count"), lit(0)).alias("total_tqc_count"),
            coalesce(col("tqc_prev.total_tqc_count"), lit(0)).alias(
                "_prior_month_tqc_count"
            ),
            col("vfl_curr.ts_valid_activation_first_listing"),
            coalesce(col("vfl_curr.total_listings_count"), lit(0)).alias(
                "total_listings_count"
            ),
            coalesce(col("vfl_prev.total_listings_count"), lit(0)).alias(
                "_prior_month_listings_count"
            ),
            coalesce(col("ppa_curr.total_ppa_count"), lit(0)).alias("total_ppa_count"),
            coalesce(col("ppa_prev.total_ppa_count"), lit(0)).alias(
                "_prior_month_ppa_count"
            ),
            col("ppa_curr.ts_first_ppa_activation"),
            col("city.name_city"),
            col("da.is_sale_agent").alias("_bctx_is_sale"),
            col("da.is_rent_agent").alias("_bctx_is_rent"),
        )
        .withColumn(
            "is_ciq_active_in_month",
            (col("total_listings_count") + col("_prior_month_listings_count")) > 0,
        )
        .withColumn(
            "is_tqc_active_in_month",
            (col("total_tqc_count") + col("_prior_month_tqc_count")) > 0,
        )
        .withColumn(
            "is_ppa_active_in_month",
            (col("total_ppa_count") + col("_prior_month_ppa_count")) > 0,
        )
        .withColumn(
            "is_activated",
            col("is_ciq_active_in_month")
            | col("is_tqc_active_in_month")
            | col("is_ppa_active_in_month"),
        )
        .drop(
            "_prior_month_listings_count",
            "_prior_month_tqc_count",
            "_prior_month_ppa_count",
        )
        .withColumn(
            "is_ciq_only",
            (col("ciq_status") == "ACTIVE") & (col("agent_status") == "INACTIVE"),
        )
        .withColumn(
            "is_independent_agent",
            (col("ciq_status") == "ACTIVE")
            & (col("agent_status") == "ACTIVE")
            & ~col("is_passive_lead_receiver"),
        )
        .withColumn("agent_type_segment", agent_type_segment)
        .withColumn(
            "agent_business_context",
            when(
                coalesce(col("_bctx_is_sale"), lit(False))
                & coalesce(col("_bctx_is_rent"), lit(False)),
                lit("FOR_SALE_AND_FOR_RENT"),
            )
            .when(coalesce(col("_bctx_is_sale"), lit(False)), lit("FOR_SALE"))
            .when(coalesce(col("_bctx_is_rent"), lit(False)), lit("FOR_RENT"))
            .otherwise(lit("UNKNOWN")),
        )
        .drop("_bctx_is_sale", "_bctx_is_rent")
        .withColumn(
            "days_since_demand_agent_created",
            datediff(
                last_day(col("reference_month")), to_date(col("ts_agent_created"))
            ),
        )
        .withColumn(
            "days_since_ciq_created",
            datediff(last_day(col("reference_month")), to_date(col("ts_ciq_created"))),
        )
        .withColumn(
            "days_since_independent_agent_registered",
            datediff(
                last_day(col("reference_month")), col("dt_independent_agent_registered")
            ),
        )
    )


# COMMAND ----------

# DBTITLE 1,Pre-write validations
EXPECTED_SCHEMA = StructType(
    [
        StructField("id_user", LongType(), True),
        StructField("id_agent", LongType(), True),
        StructField("reference_month", DateType(), True),
        StructField("ciq_status", StringType(), True),
        StructField("agent_status", StringType(), True),
        StructField("is_passive_lead_receiver", BooleanType(), True),
        StructField("dt_independent_agent_registered", DateType(), True),
        StructField("ts_agent_created", TimestampType(), True),
        StructField("ts_ciq_created", TimestampType(), True),
        StructField("ts_first_activation_tqc_referral", TimestampType(), True),
        StructField("total_tqc_count", LongType(), False),
        StructField("ts_valid_activation_first_listing", TimestampType(), True),
        StructField("total_listings_count", LongType(), False),
        StructField("total_ppa_count", LongType(), False),
        StructField("ts_first_ppa_activation", TimestampType(), True),
        StructField("is_ciq_active_in_month", BooleanType(), False),
        StructField("is_tqc_active_in_month", BooleanType(), False),
        StructField("is_ppa_active_in_month", BooleanType(), False),
        StructField("is_activated", BooleanType(), False),
        StructField("is_ciq_only", BooleanType(), False),
        StructField("is_independent_agent", BooleanType(), False),
        StructField("agent_type_segment", StringType(), True),
        StructField("agent_business_context", StringType(), True),
        StructField("name_city", StringType(), True),
        StructField("days_since_demand_agent_created", IntegerType(), True),
        StructField("days_since_ciq_created", IntegerType(), True),
        StructField("days_since_independent_agent_registered", IntegerType(), True),
    ]
)


def _schema_mismatches(actual: StructType, expected: StructType) -> list[str]:
    actual_by_name = {f.name: f for f in actual.fields}
    expected_by_name = {f.name: f for f in expected.fields}
    mismatch_list = []
    for name in actual_by_name.keys() | expected_by_name.keys():
        if name not in actual_by_name:
            mismatch_list.append(f"missing: {name}")
        elif name not in expected_by_name:
            mismatch_list.append(f"unexpected: {name}")
        elif (
            actual_by_name[name].dataType.simpleString()
            != expected_by_name[name].dataType.simpleString()
        ):
            mismatch_list.append(
                f"{name}: expected {expected_by_name[name].dataType.simpleString()}, "
                f"got {actual_by_name[name].dataType.simpleString()}"
            )
    return mismatch_list


UNIQUE_KEY_COLUMNS = ["id_user", "reference_month"]


def _assert_unique_on_key(source_df: DataFrame, key_columns: list[str]) -> None:
    """Raise if key_columns are not unique (duplicate rows for the same key)."""
    row_count = source_df.count()
    distinct_count = source_df.select(key_columns).distinct().count()
    if row_count != distinct_count:
        duplicate_count = row_count - distinct_count
        raise ValueError(
            f"Duplicate key: {key_columns} must be unique; "
            f"rows={row_count:,}, distinct keys={distinct_count:,}, duplicates={duplicate_count:,}"
        )


def validate_before_write(source_df: DataFrame) -> int:
    """Validate non-empty, schema, and id_user+reference_month uniqueness; return row count for logging."""
    row_count = source_df.count()
    if row_count == 0:
        raise ValueError("Dataset is empty; aborting write.")
    mismatches = _schema_mismatches(source_df.schema, EXPECTED_SCHEMA)
    if mismatches:
        raise ValueError(f"Schema mismatch: {'; '.join(mismatches)}")
    _assert_unique_on_key(source_df, UNIQUE_KEY_COLUMNS)
    logger.info(
        f"m=validate_before_write, rows={row_count:,}, schema OK, "
        f"key {UNIQUE_KEY_COLUMNS} unique"
    )
    return row_count


# COMMAND ----------


# DBTITLE 1,Writing
def _save_to_enrich(
    spark_client: SparkClient, result_df: DataFrame, args: Namespace, row_count: int
) -> None:
    db_info = DatalakeMetastoreService.get_db_info(
        args.env, args.database_base_name, args.datalake_bucket
    )
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=args.table_name,
            prod_location=database_location,
            bucket=args.datalake_bucket,
            target_database=getattr(args, "target_database_name", None),
            target_table=getattr(args, "target_table_name", None),
        )
    )
    full_table_name = f"{write_database_name}.{write_table_name}"
    s3_path = f"{write_location}{write_table_name}"

    SparkMetastoreService(spark_client).create_database(write_database_name)
    DeltaLoader().load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=result_df,
        partition_by=["reference_month"],
        merge_on=["id_user", "reference_month"],
    )
    SparkMetastoreService(spark_client).refresh_table(
        write_database_name, write_table_name
    )
    priv = TablePrivileges.from_environment_default(full_table_name)
    if priv and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        priv.apply()
    logger.info(f"m=save_df, table={full_table_name}, rows={row_count:,}")


def save_df(
    spark_client: SparkClient,
    result_df: DataFrame,
    args: Namespace,
    row_count: Optional[int] = None,
) -> None:
    run_mode = getattr(args, "run_mode", "dev")
    if run_mode == "prod":
        _save_to_enrich(
            spark_client,
            result_df,
            args,
            row_count if row_count is not None else result_df.count(),
        )
        return
    view_name = f"dev_{args.table_name}"
    result_df.cache()
    n = result_df.count()
    result_df.createOrReplaceTempView(view_name)
    logger.info(
        f"Dev mode: temp view '{view_name}' ({n:,} rows). SELECT * FROM {view_name}"
    )


# COMMAND ----------


# DBTITLE 1,Main
def main(args: Optional[Namespace] = None) -> None:
    if args is None:
        args = parse_args()
    logger.info(
        f"m=main, run_mode={args.run_mode}, table={args.table_name}, "
        f"load_end_date={args.load_end_date}, months_window={args.months_window}"
    )
    df = build_agent_new_agent_activation_metrics(args)
    row_count = validate_before_write(df)
    save_df(SparkClient(), df, args, row_count=row_count)
    logger.info("m=main, msg=Job finished successfully")


if __name__ == "__main__":
    main()
