# Databricks notebook source
# DBTITLE 1,Local dev configuration
# MAGIC %run "/Workspace/Data Engineering/Data Partners/1. Utils/templates/local_config"

# COMMAND ----------
#
# load_agent_new_agent_activation_daily — ETL summary
# ---------------------------------------------------------------------------
# Writes: enrich schema table agent_new_agent_activation_daily (Delta, merge on
# id_agent + dt_reference, partitions year/month/day).
#
# Grain: one row per (id_agent, dt_reference) from agent creation through
# min(load_end_date, creation + max_tracking_days_after_creation). After that
# cap the agent drops out of the cohort (no further rows merged).
#
# Cohort: newly accredited agents — accreditation timestamp (earliest
# ``AGENT_ACTIVATED`` event in ``agent_event_log``, ``id_capability IS NULL``)
# on/after ``cohort_start_date`` (default 2025-01-01), excluding
# Vistoria / VistoriaQuarteirizada / SessaoFotos.
# Source reads are bounded by the load interval (default 14 days) and ``load_end_date``;
# activation still uses events from ``cohort_start_date`` through ``load_end_date``.
#
# Activation: at least one qualifying event within ``activation_window_weeks``
# (default 4) after ``ts_agent_created``:
#   CIQ  — valid first listing (``ciq_first_listing``, join on id_user)
#   TQC  — self-referral (``offer_specialists``, join on id_user)
#   VCBA — completed visit booked by the agent, ``id_user_creation = id_user_agent``
#          (``visit_schedules``, join on id_agent)
# ``is_activated`` is as-of-day (true from the first qualifying event date on);
# ``activation_reason`` / ``dt_activated`` are frozen per agent (earliest event,
# tie-break CIQ > TQC > VCBA).
#
# Capacity split: ``is_passive_lead_receiver`` as-of-day from ``agent_data_aud``
# history (fallback to current ``agent_data`` value) →
# ``agent_capacity_segment`` CAPACITY (passive) / NON_CAPACITY.
#
# How to run unit tests (repo root):
#   cd packages/bietlejuice-runtime && PYTHONPATH=src:../.. uv run --project envs/dbr-16-4 pytest test/dags/agents/enrich_agent_reports/spark_jobs/test_load_agent_new_agent_activation_daily.py -v
#

# DBTITLE 1,Import libs
from __future__ import annotations

from argparse import ArgumentParser, Namespace
from datetime import date, datetime, timedelta
from typing import Optional

from pyspark.sql import DataFrame, SparkSession, Window
from pyspark.sql.functions import (
    coalesce,
    col,
    count,
    countDistinct,
    date_add,
    dayofmonth,
    explode,
    expr,
    lead,
    lit,
    month,
    row_number,
    to_date,
    when,
    year,
)
from pyspark.sql.functions import min as spark_min
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
JOB_NAME = "load_agent_new_agent_activation_daily"
logger = QuintoAndarLogger(JOB_NAME)

ACTIVATION_WINDOW_WEEKS_DEFAULT = 4
COHORT_START_DATE_DEFAULT = "2025-01-01"
# Daily rows are emitted only through creation + N calendar days (inclusive cap day).
MAX_TRACKING_DAYS_AFTER_CREATION_DEFAULT = 90
# Inclusive calendar days rebuilt per scheduled run (load_end − lookback … load_end).
REPROCESS_LOOKBACK_DAYS = 13

TABLE_AGENT_DATA = "datalake_ebdb_clean.agent_data"
TABLE_AGENT_DATA_AUD = "datalake_ebdb_clean.agent_data_aud"
TABLE_USER = "datalake_ebdb_user.user"
TABLE_OFFER_SPECIALISTS = "datalake_sale_offer_flows.offer_specialists"
TABLE_CIQ_FIRST_LISTING = "datalake_tiers.ciq_first_listing"
TABLE_VISIT_SCHEDULES = "datalake_visit.visit_schedules"
TABLE_AGENT_EVENT_LOG = "datalake_ebdb_clean.agent_event_log"

EXCLUDED_AGENT_TYPES = ["Vistoria", "VistoriaQuarteirizada", "SessaoFotos"]
# Accreditation is the earliest agent-level AGENT_ACTIVATED event (not row creation).
AGENT_ACCREDITATION_EVENT_TYPE = "AGENT_ACTIVATED"

REASON_CIQ = "CIQ"
REASON_TQC = "TQC"
REASON_VCBA = "VCBA"
# Tie-break when two reasons share the same first-event timestamp.
REASON_PRIORITY = {REASON_CIQ: 1, REASON_TQC: 2, REASON_VCBA: 3}

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
        "agent_new_agent_activation_daily",
        "Target enrich table name",
    ),
    (
        "load_start_date",
        str,
        lambda: (date.today() - timedelta(days=REPROCESS_LOOKBACK_DAYS)).isoformat(),
        "Interval start YYYY-MM-DD (first dt_reference rebuilt)",
    ),
    (
        "load_end_date",
        str,
        lambda: date.today().isoformat(),
        "Interval end YYYY-MM-DD (last dt_reference rebuilt)",
    ),
    ("run_mode", str, "dev", "Run mode: prod/dev"),
    (
        "activation_window_weeks",
        int,
        ACTIVATION_WINDOW_WEEKS_DEFAULT,
        "X: weeks after agent creation within which an activation event counts",
    ),
    (
        "cohort_start_date",
        str,
        COHORT_START_DATE_DEFAULT,
        "Only agents created on/after this date enter the table",
    ),
    (
        "max_tracking_days_after_creation",
        int,
        MAX_TRACKING_DAYS_AFTER_CREATION_DEFAULT,
        "Last dt_reference is at most this many days after agent creation",
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


def _filter_dt_event_range(events: DataFrame, start: date, end: date) -> DataFrame:
    """Restrict pre-aggregated daily event rows to an inclusive date range."""
    return events.filter(
        (col("dt_event") >= lit(start.isoformat()))
        & (col("dt_event") <= lit(end.isoformat()))
    )


# DBTITLE 1,Cohort (newly accredited agents)
def _cohort_df(
    spark: SparkSession,
    cohort_start_date: str,
    load_start: date,
    load_end: date,
    max_tracking_days: int,
) -> DataFrame:
    """One row per new agent: id_agent, id_user, ts_agent_created, current passive flag.

    ``ts_agent_created`` is the agent's accreditation timestamp — the earliest
    agent-level ``AGENT_ACTIVATED`` event (``id_capability IS NULL``) in
    ``agent_event_log`` — not ``agent_data.ts_created`` (the row-creation time).
    Excludes vistoria/foto personas and agents outside the cohort start or load window.
    Agents whose tracking window (accreditation … accreditation + max_tracking_days) no
    longer overlaps [load_start, load_end] are excluded.
    ``id_user`` resolved via the user table (min id per agent, ignoring -1).
    """
    cohort_floor = max(
        datetime.strptime(cohort_start_date, "%Y-%m-%d").date(),
        load_start - timedelta(days=max_tracking_days),
    ).isoformat()
    accreditation = (
        spark.table(TABLE_AGENT_EVENT_LOG)
        .filter(col("id_capability").isNull())
        .filter(col("event_type") == lit(AGENT_ACCREDITATION_EVENT_TYPE))
        .filter(col("ts_occurred").isNotNull())
        .groupBy("id_agent")
        .agg(spark_min("ts_occurred").alias("ts_agent_created"))
        .filter(to_date(col("ts_agent_created")) >= lit(cohort_floor))
        .filter(to_date(col("ts_agent_created")) >= lit(cohort_start_date))
        .filter(to_date(col("ts_agent_created")) <= lit(load_end.isoformat()))
        .filter(
            date_add(to_date(col("ts_agent_created")), max_tracking_days)
            >= lit(load_start.isoformat())
        )
    )
    agents = (
        spark.table(TABLE_AGENT_DATA)
        .filter(~col("agent_type").isin(EXCLUDED_AGENT_TYPES))
        .select(
            col("id").alias("id_agent"),
            col("is_passive_lead_receiver").alias("_current_passive"),
        )
    )
    cohort = accreditation.join(agents, on="id_agent", how="inner")
    users = (
        spark.table(TABLE_USER)
        .filter(col("id") != -1)
        .groupBy(col("id_agent").alias("usr_id_agent"))
        .agg(spark_min("id").alias("id_user"))
    )
    return cohort.join(users, col("id_agent") == col("usr_id_agent"), "left").drop(
        "usr_id_agent"
    )


# COMMAND ----------


# DBTITLE 1,Activation events by day (CIQ / TQC / VCBA)
def _tqc_events_df(
    spark: SparkSession, event_start_date: str, event_end_date: str
) -> DataFrame:
    """TQC self-referrals per (id_user, dt_event): daily count + first ts of the day."""
    return (
        spark.table(TABLE_OFFER_SPECIALISTS)
        .filter(col("id_user_agent_lead_referral") == col("id_user_agent"))
        .filter(col("ts_agent_lead_referral_updated").isNotNull())
        .withColumn("dt_event", to_date(col("ts_agent_lead_referral_updated")))
        .filter(col("dt_event") >= lit(event_start_date))
        .filter(col("dt_event") <= lit(event_end_date))
        .groupBy(col("id_user_agent").alias("id_user"), "dt_event")
        .agg(
            count("id_offer").alias("event_count"),
            spark_min("ts_agent_lead_referral_updated").alias("ts_first_event"),
        )
    )


def _ciq_events_df(
    spark: SparkSession, event_start_date: str, event_end_date: str
) -> DataFrame:
    """Valid first listings per (id_user, dt_event): daily count + first ts of the day."""
    return (
        spark.table(TABLE_CIQ_FIRST_LISTING)
        .filter(col("is_first_listing_valid") == True)  # noqa: E712
        .filter(col("ts_original_first_listing").isNotNull())
        .withColumn("dt_event", to_date(col("ts_original_first_listing")))
        .filter(col("dt_event") >= lit(event_start_date))
        .filter(col("dt_event") <= lit(event_end_date))
        .groupBy("id_user", "dt_event")
        .agg(
            count("*").alias("event_count"),
            spark_min("ts_original_first_listing").alias("ts_first_event"),
        )
    )


def _vcba_events_df(
    spark: SparkSession, event_start_date: str, event_end_date: str
) -> DataFrame:
    """VCBA — completed visits booked by the agent (id_user_creation = id_user_agent)
    per (id_agent, dt_event): daily distinct-schedule count + first ts of the day."""
    return (
        spark.table(TABLE_VISIT_SCHEDULES)
        .filter(col("is_completed") == True)  # noqa: E712
        .filter(col("ts_schedule_visit").isNotNull())
        .filter(col("id_user_creation") == col("id_user_agent"))
        .withColumn("dt_event", to_date(col("ts_schedule_visit")))
        .filter(col("dt_event") >= lit(event_start_date))
        .filter(col("dt_event") <= lit(event_end_date))
        .groupBy("id_agent", "dt_event")
        .agg(
            countDistinct("id_schedule").alias("event_count"),
            spark_min("ts_schedule_visit").alias("ts_first_event"),
        )
    )


# COMMAND ----------


# DBTITLE 1,First qualifying event per agent (within window)
def _activation_summary_df(
    cohort: DataFrame,
    tqc_events: DataFrame,
    ciq_events: DataFrame,
    vcba_events: DataFrame,
    activation_window_weeks: int,
) -> DataFrame:
    """id_agent, dt_activated, activation_reason from the earliest qualifying event
    whose date falls in [dt_created, dt_created + weeks*7]. Tie-break CIQ > TQC > VCBA."""
    window_days = activation_window_weeks * 7
    keyed = cohort.select(
        "id_agent",
        "id_user",
        to_date(col("ts_agent_created")).alias("_dt_created"),
        date_add(to_date(col("ts_agent_created")), window_days).alias("_dt_deadline"),
    )

    def _candidates(events: DataFrame, join_col: str, reason: str) -> DataFrame:
        return (
            events.join(keyed, on=join_col, how="inner")
            .filter(
                (col("dt_event") >= col("_dt_created"))
                & (col("dt_event") <= col("_dt_deadline"))
            )
            .groupBy("id_agent")
            .agg(spark_min("ts_first_event").alias("ts_event"))
            .withColumn("activation_reason", lit(reason))
            .withColumn("_priority", lit(REASON_PRIORITY[reason]))
        )

    candidates = (
        _candidates(ciq_events, "id_user", REASON_CIQ)
        .unionByName(_candidates(tqc_events, "id_user", REASON_TQC))
        .unionByName(_candidates(vcba_events, "id_agent", REASON_VCBA))
    )
    first_window = Window.partitionBy("id_agent").orderBy(
        col("ts_event"), col("_priority")
    )
    return (
        candidates.withColumn("_rn", row_number().over(first_window))
        .filter(col("_rn") == 1)
        .select(
            "id_agent",
            to_date(col("ts_event")).alias("dt_activated"),
            "activation_reason",
        )
    )


# COMMAND ----------


# DBTITLE 1,Passive-lead-receiver history (agent_data_aud)
def _passive_periods_df(
    spark: SparkSession, cohort: DataFrame, load_start: date, load_end: date
) -> DataFrame:
    """Validity periods of is_passive_lead_receiver per agent from the audit log.

    One row per (id_agent, ts_valid_from) with ts_valid_to = next change (null = open).
    Limited to cohort agents and periods overlapping the rebuild window.
    """
    cohort_agents = cohort.select(col("id_agent").alias("aud_id_agent")).distinct()
    events = (
        spark.table(TABLE_AGENT_DATA_AUD)
        .filter(col("ts_database_transaction").isNotNull())
        .join(cohort_agents, col("id") == col("aud_id_agent"), "left_semi")
        .select(
            col("id").alias("aud_id_agent"),
            col("is_passive_lead_receiver").alias("aud_passive"),
            col("ts_database_transaction"),
        )
        .groupBy("aud_id_agent", "ts_database_transaction")
        .agg(spark_min(col("aud_passive")).alias("aud_passive"))
    )
    w = Window.partitionBy("aud_id_agent").orderBy("ts_database_transaction")
    return (
        events.withColumn("ts_valid_from", col("ts_database_transaction"))
        .withColumn("ts_valid_to", lead("ts_database_transaction").over(w))
        .filter(
            (to_date(col("ts_valid_from")) <= lit(load_end.isoformat()))
            & (
                col("ts_valid_to").isNull()
                | (to_date(col("ts_valid_to")) >= lit(load_start.isoformat()))
            )
        )
        .select("aud_id_agent", "aud_passive", "ts_valid_from", "ts_valid_to")
    )


# COMMAND ----------


# DBTITLE 1,Main builder
def build_agent_new_agent_activation_daily(
    spark: SparkSession, args: Namespace
) -> DataFrame:
    """Daily activation fact for newly accredited agents (see header for semantics)."""
    weeks = int(args.activation_window_weeks)
    cohort_start = args.cohort_start_date
    max_tracking_days = int(args.max_tracking_days_after_creation)
    # Validate date strings early — guards the expr() sequence interpolation below.
    load_start = datetime.strptime(args.load_start_date, "%Y-%m-%d").date()
    load_end = datetime.strptime(args.load_end_date, "%Y-%m-%d").date()
    window_days = weeks * 7
    event_end = load_end.isoformat()
    event_start = max(
        datetime.strptime(cohort_start, "%Y-%m-%d").date(),
        load_start - timedelta(days=max_tracking_days),
    ).isoformat()

    cohort = _cohort_df(spark, cohort_start, load_start, load_end, max_tracking_days)
    tqc_events = _tqc_events_df(spark, event_start, event_end)
    ciq_events = _ciq_events_df(spark, event_start, event_end)
    vcba_events = _vcba_events_df(spark, event_start, event_end)
    activation = _activation_summary_df(
        cohort, tqc_events, ciq_events, vcba_events, weeks
    )
    passive_periods = _passive_periods_df(spark, cohort, load_start, load_end)
    tqc_daily = _filter_dt_event_range(tqc_events, load_start, load_end)
    ciq_daily = _filter_dt_event_range(ciq_events, load_start, load_end)
    vcba_daily = _filter_dt_event_range(vcba_events, load_start, load_end)

    spine = (
        cohort.filter(to_date(col("ts_agent_created")) <= lit(load_end))
        .withColumn(
            "dt_tracking_end",
            date_add(to_date(col("ts_agent_created")), max_tracking_days),
        )
        .withColumn(
            "dt_reference",
            explode(
                expr(
                    f"sequence("
                    f"greatest(to_date(ts_agent_created), to_date('{load_start.isoformat()}')), "
                    f"least(to_date('{load_end.isoformat()}'), dt_tracking_end), "
                    f"interval 1 day)"
                )
            ),
        )
        .withColumn(
            "dt_activation_deadline",
            date_add(to_date(col("ts_agent_created")), window_days),
        )
    )

    return (
        spine.join(
            tqc_daily.select(
                col("id_user").alias("tqc_id_user"),
                col("dt_event").alias("tqc_dt"),
                col("event_count").alias("tqc_count"),
            ),
            (col("id_user") == col("tqc_id_user"))
            & (col("dt_reference") == col("tqc_dt")),
            "left",
        )
        .join(
            ciq_daily.select(
                col("id_user").alias("ciq_id_user"),
                col("dt_event").alias("ciq_dt"),
                col("event_count").alias("ciq_count"),
            ),
            (col("id_user") == col("ciq_id_user"))
            & (col("dt_reference") == col("ciq_dt")),
            "left",
        )
        .join(
            vcba_daily.select(
                col("id_agent").alias("vcba_id_agent"),
                col("dt_event").alias("vcba_dt"),
                col("event_count").alias("vcba_count"),
            ),
            (col("id_agent") == col("vcba_id_agent"))
            & (col("dt_reference") == col("vcba_dt")),
            "left",
        )
        .join(activation, on="id_agent", how="left")
        .join(
            passive_periods,
            (col("id_agent") == col("aud_id_agent"))
            & (col("dt_reference") >= to_date(col("ts_valid_from")))
            & (
                col("ts_valid_to").isNull()
                | (col("dt_reference") < to_date(col("ts_valid_to")))
            ),
            "left",
        )
        .withColumn(
            "is_passive_lead_receiver",
            coalesce(col("aud_passive"), col("_current_passive")),
        )
        .select(
            col("id_agent"),
            col("id_user"),
            when(coalesce(col("is_passive_lead_receiver"), lit(False)), lit("CAPACITY"))
            .otherwise(lit("NON_CAPACITY"))
            .alias("agent_capacity_segment"),
            col("activation_reason"),
            lit(weeks).cast("int").alias("activation_window_weeks"),
            coalesce(col("tqc_count"), lit(0)).alias("total_tqc_count"),
            coalesce(col("vcba_count"), lit(0)).alias("total_vcba_count"),
            coalesce(col("ciq_count"), lit(0)).alias("total_listings_count"),
            col("is_passive_lead_receiver"),
            (col("dt_reference") <= col("dt_activation_deadline")).alias("is_eligible"),
            (
                col("dt_activated").isNotNull()
                & (col("dt_reference") >= col("dt_activated"))
            ).alias("is_activated"),
            col("dt_reference"),
            col("dt_activation_deadline"),
            col("dt_activated"),
            col("ts_agent_created"),
            year(col("dt_reference")).alias("year"),
            month(col("dt_reference")).alias("month"),
            dayofmonth(col("dt_reference")).alias("day"),
        )
    )


# COMMAND ----------

# DBTITLE 1,Pre-write validations
EXPECTED_SCHEMA = StructType(
    [
        StructField("id_agent", LongType(), True),
        StructField("id_user", LongType(), True),
        StructField("agent_capacity_segment", StringType(), False),
        StructField("activation_reason", StringType(), True),
        StructField("activation_window_weeks", IntegerType(), False),
        StructField("total_tqc_count", LongType(), False),
        StructField("total_vcba_count", LongType(), False),
        StructField("total_listings_count", LongType(), False),
        StructField("is_passive_lead_receiver", BooleanType(), True),
        StructField("is_eligible", BooleanType(), True),
        StructField("is_activated", BooleanType(), True),
        StructField("dt_reference", DateType(), True),
        StructField("dt_activation_deadline", DateType(), True),
        StructField("dt_activated", DateType(), True),
        StructField("ts_agent_created", TimestampType(), True),
        StructField("year", IntegerType(), True),
        StructField("month", IntegerType(), True),
        StructField("day", IntegerType(), True),
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


UNIQUE_KEY_COLUMNS = ["id_agent", "dt_reference"]


def validate_before_write(source_df: DataFrame) -> int:
    """Validate non-empty, schema, and id_agent+dt_reference uniqueness; return row count."""
    row_count = source_df.count()
    if row_count == 0:
        raise ValueError("Dataset is empty; aborting write.")
    mismatches = _schema_mismatches(source_df.schema, EXPECTED_SCHEMA)
    if mismatches:
        raise ValueError(f"Schema mismatch: {'; '.join(mismatches)}")
    distinct_count = source_df.select(UNIQUE_KEY_COLUMNS).distinct().count()
    if row_count != distinct_count:
        raise ValueError(
            f"Duplicate key: {UNIQUE_KEY_COLUMNS} must be unique; "
            f"rows={row_count:,}, distinct keys={distinct_count:,}, "
            f"duplicates={row_count - distinct_count:,}"
        )
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
        partition_by=["year", "month", "day"],
        merge_on=UNIQUE_KEY_COLUMNS,
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
    row_count: int,
) -> None:
    run_mode = getattr(args, "run_mode", "dev")
    if run_mode == "prod":
        _save_to_enrich(spark_client, result_df, args, row_count)
        return
    view_name = f"dev_{args.table_name}"
    result_df.createOrReplaceTempView(view_name)
    logger.info(
        f"Dev mode: temp view '{view_name}' ({row_count:,} rows). SELECT * FROM {view_name}"
    )


# COMMAND ----------


# DBTITLE 1,Main
def main(args: Optional[Namespace] = None) -> None:
    if args is None:
        args = parse_args()
    logger.info(
        f"m=main, run_mode={args.run_mode}, table={args.table_name}, "
        f"load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, "
        f"activation_window_weeks={args.activation_window_weeks}, "
        f"cohort_start_date={args.cohort_start_date}, "
        f"max_tracking_days_after_creation={args.max_tracking_days_after_creation}"
    )
    spark_client = SparkClient(app_name=JOB_NAME)
    df = build_agent_new_agent_activation_daily(spark_client.conn, args)
    row_count = validate_before_write(df)
    save_df(spark_client, df, args, row_count=row_count)
    logger.info("m=main, msg=Job finished successfully")


if __name__ == "__main__":
    main()
