# Databricks notebook source
# DBTITLE 1,Local dev configuration
# MAGIC %run "/Workspace/Data Engineering/Data Partners/1. Utils/templates/local_config"

# COMMAND ----------

# DBTITLE 1,Import libs
from argparse import ArgumentParser, Namespace
from datetime import date, timedelta, datetime
from dateutil.relativedelta import relativedelta
import os
from typing import Optional

from pyspark.sql import DataFrame, Window
from pyspark.sql.functions import (
    add_months,
    coalesce,
    col,
    collect_list,
    count,
    countDistinct,
    date_trunc,
    explode,
    expr,
    lit,
    row_number,
    sequence,
    struct,
    sum as spark_sum,
    to_date,
)

from pyspark.sql.types import (
    ArrayType,
    BooleanType,
    DateType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.spark.base_spark import BaseSparkContext
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger

# COMMAND ----------

# DBTITLE 1,Setup & Constants
JOB_NAME = "load_agent_support_tickets_by_month"
logger = QuintoAndarLogger(JOB_NAME)

# Constants to avoid magic values; single place to change behavior of simple business rules
AGENT_STATUS_ACTIVE = "ACTIVE"
AGENT_STATUS_INACTIVE = "INACTIVE"
MIN_VISITS_FOR_ACTIVE_AGENT = 1
MIN_LISTINGS_FOR_ACTIVE_CIQ = 1


TABLE_CIQ_FIRST_LISTING   = "datalake_tiers.ciq_first_listing"
TABLE_BOOKING             = "datalake_booking.booking"
TABLE_PARTNER             = "datalake_ebdb_clean.partner"
TABLE_PARTNER_AGENT       = "datalake_ebdb_clean.partner_agent"
TABLE_DIM_USER            = "dw_public.dim_user"
TABLE_AGENT_DATA          = "datalake_ebdb_clean.agent_data"
TABLE_CIQ_AGENTS          = "datalake_ebdb_agents.ciq_agents"
TABLE_DIM_AGENT           = "dw_public.dim_agent"
TABLE_FACT_TICKETS        = "dw_customer_support.fact_tickets"
TABLE_DIM_TAXONOMY        = "dw_customer_support.dim_taxonomy"
TABLE_STATUS_BY_MONTH     = "datalake_agent_reports.agent_status_by_month"

# COMMAND ----------

# DBTITLE 1,Argument parsing
ARG_SPEC = [
    ("env", str, "forno", "Environment: forno/prod"),
    ("datalake_bucket", str, "5a-datalake-prod", "Datalake bucket"),
    ("database_base_name", str, "agent_reports", "Base name for database (schema)"),
    ("dag_name", str, "enrich_agent_reports", "DAG name"),
    ("table_name", str, "agent_support_tickets_by_month", "Target enrich table name"),
    ("load_start_date", str, lambda: (date.today() - timedelta(days=30)).isoformat(), "Interval start YYYY-MM-DD"),
    ("load_end_date", str, lambda: date.today().isoformat(), "Interval end YYYY-MM-DD (window end date)"),
    ("run_mode", str, "dev", "Run mode: prod/dev"),
    ("months_window", int, 18, "Number of months in the lookback window"),
]

def _defaults():
    return [d() if callable(d) else d for _, _, d, _ in ARG_SPEC]

def parse_args() -> Namespace:
    """Parse CLI args. Each positional is optional (nargs='?') so notebook runs with no args use defaults.
    Uses parse_known_args() so kernel flags (e.g. -f) are ignored when run from Databricks notebook."""
    parser = ArgumentParser(description=JOB_NAME)
    default_values = _defaults()
    for (name, type_, _default, help_text), default_val in zip(ARG_SPEC, default_values):
        parser.add_argument(name, nargs="?", type=type_, default=default_val, help=help_text)
    namespace, _ = parser.parse_known_args()
    return namespace

# --- Date range: last N months (inclusive) from interval end ---
def _month_range(load_end_date: str, months_window: int = 18) -> tuple[date, date]:
    """Return (month_start, month_end) as Python dates (first day of each month) for the lookback window."""
    num_months = int(months_window)
    end_date = datetime.strptime(load_end_date, "%Y-%m-%d").date()
    month_end = end_date.replace(day=1)
    month_start = month_end - relativedelta(months=num_months - 1)
    return month_start, month_end

# COMMAND ----------

# DBTITLE 1,Helper functions
def _month_range(load_end_date: str, months_window: int = 18) -> tuple[date, date]:
    """Return (month_start, month_end) as Python dates (first day of each month) for the lookback window."""
    num_months = int(months_window)
    end_date = datetime.strptime(load_end_date, "%Y-%m-%d").date()
    month_end = end_date.replace(day=1)
    month_start = month_end - relativedelta(months=num_months - 1)
    return month_start, month_end


def _month_expanded(
    source_df: DataFrame, start_expr, end_expr, new_col: str = "month_ref"
) -> DataFrame:
    """
    Add a column with one row per month from start_expr to end_expr (inclusive), step 1 month.
    start_expr and end_expr are PySpark Column expressions (e.g. col("x"), add_months(col("x"), 1)).
    """
    return source_df.withColumn(
        new_col,
        explode(
            sequence(
                start_expr,
                end_expr,
                expr("interval 1 month"),
            )
        ),
    )

def _filter_in_month_window(
    source_df: DataFrame, month_col: str, month_start: date, month_end: date
) -> DataFrame:
    """Filter rows whose month_col is within [month_start, month_end] (inclusive). Uses df[col] so Column type matches the DataFrame session (avoids sql.column vs sql.connect.column mismatch in .py)."""
    month_col_ref = source_df[month_col]
    return source_df.filter(
        (month_col_ref >= month_start) & (month_col_ref <= month_end)
    )

# COMMAND ----------

# DBTITLE 1,Business rules
def _qualified_active_ciqs_by_month(load_end_date: str, months_window: int = 18) -> DataFrame:
    """Agent-months where the agent has a valid first listing in a 3-month window (first listing month + 2 following)."""
    month_start, month_end = _month_range(load_end_date, months_window)
    first_listing = (
        spark.table(TABLE_CIQ_FIRST_LISTING)
        .filter(col("is_first_listing_valid") == True)
        .filter(col("ts_original_first_listing").isNotNull())
        .select(
            col("id_user"),
            date_trunc("month", col("ts_original_first_listing")).alias("listing_month_start"),
            add_months(date_trunc("month", col("ts_original_first_listing")), 2).alias("listing_month_end"),
        )
    )
    qualified_user_months = _month_expanded(
        first_listing,
        col("listing_month_start"),
        col("listing_month_end"),
    )
    return (
        _filter_in_month_window(qualified_user_months, "month_ref", month_start, month_end)
        .select(col("id_user"), to_date(col("month_ref")).alias("reference_month"))
        .distinct()
    )


def _all_listings_by_month(load_end_date: str, months_window: int = 18) -> DataFrame:
    """Count of all CIQ listings per (id_user, reference_month) in the window."""
    month_start, month_end = _month_range(load_end_date, months_window)
    ciq_listings_with_month = (
        spark.table(TABLE_CIQ_FIRST_LISTING)
        .filter(col("ts_original_first_listing").isNotNull())
        .withColumn(
            "reference_month",
            to_date(date_trunc("month", col("ts_original_first_listing"))),
        )
    )
    listings_in_window = _filter_in_month_window(
        ciq_listings_with_month, "reference_month", month_start, month_end
    )
    return listings_in_window.groupBy("id_user", "reference_month").agg(
        count("*").alias("total_listings_count")
    )


# --- Visits: each completed visit counts for its month and the next (2-month window) ---
def _all_agents_visits_by_month(load_end_date: str, months_window: int = 18) -> DataFrame:
    """Count distinct visits per (id_agent, reference_month); visits counts for the month that they were made and the following month"""
    month_start, month_end = _month_range(load_end_date, months_window)
    completed_visits = (
        spark.table(TABLE_BOOKING)
        .filter(
            (col("is_visit_completed") == True)
            & col("dt_booking").isNotNull()
        )
        .withColumn(
            "visit_month",
            date_trunc("month", col("dt_booking")),
        )
        .select("id_agent", "id", "visit_month")
    )
    visits_in_window = _filter_in_month_window(
        completed_visits, "visit_month", month_start, month_end
    )
    visits_expanded = _month_expanded(
        visits_in_window,
        col("visit_month"),
        add_months(col("visit_month"), 1),
    )
    visits_with_reference_months = visits_expanded.filter(
        visits_expanded["month_ref"] <= month_end
    )
    return (
        visits_with_reference_months
        .groupBy("id_agent", "month_ref")
        .agg(countDistinct("id").alias("total_visits_count"))
        .withColumn("reference_month", to_date(col("month_ref")))
        .drop("month_ref")
    )

def _independent_agent_eligible() -> DataFrame:
    """Service criteria for eligibility for independent agents. This is how the services see independent agent, not how Operations define (they use a sheet-based control)"""
    partner = spark.table(TABLE_PARTNER).filter(col("uuid_company").isNotNull()).alias("partner")
    partner_agent = spark.table(TABLE_PARTNER_AGENT).filter(col("status") == "ACTIVE").alias("partner_agent")
    dim_user = spark.table(TABLE_DIM_USER).alias("dim_user")
    agent_data = (
        spark.table(TABLE_AGENT_DATA)
        .filter(
            (col("is_active") == True)
            & (col("agent_type") == "CORRETOR_5A")
            & (col("is_passive_lead_receiver") == False)
        )
        .alias("agent_data")
    )
    return (
        partner.join(partner_agent, col("partner.id") == col("partner_agent.id_partner"), "left")
        .join(dim_user, col("partner_agent.id_user") == col("dim_user.sk_user"), "left")
        .join(agent_data, col("dim_user.dados_agente_id") == col("agent_data.id"), "left")
        .select(
            col("dim_user.sk_user").alias("id_user"),
            col("agent_data.is_passive_lead_receiver"),
        )
        .filter(col("id_user").isNotNull())
    )


def _business_context() -> DataFrame:
    """Return the current business context for an agent. Dedupes by id_user: keep latest by ts_updated; if tied, one arbitrary."""
    window_by_user = Window.partitionBy("id_user").orderBy(col("ts_updated").desc_nulls_last(), col("id_agent"))

    ciq_agents = (
        spark.table(TABLE_CIQ_AGENTS)
        .select(
            col("id_user"),
            col("id_agent"),
            col("is_sale_agent"),
            col("is_rent_agent"),
            col("ts_updated"),
        )
        .withColumn("_rn", row_number().over(window_by_user))
        .filter(col("_rn") == 1)
        .drop("_rn", "ts_updated")
        .alias("ciq_agents")
    )
    dim_agent = (
        spark.table(TABLE_DIM_AGENT)
        .select(
            col("sk_agent").alias("id_agent"),
            col("sk_user").alias("id_user"),
            col("is_sale_agent"),
            col("is_rent_agent"),
        )
        .alias("dim_agent")
    )
    return (
        ciq_agents.join(dim_agent, col("ciq_agents.id_user") == col("dim_agent.id_user"), "full_outer")
        .select(
            coalesce(col("ciq_agents.id_user"), col("dim_agent.id_user")).alias("id_user"),
            coalesce(col("ciq_agents.id_agent"), col("dim_agent.id_agent")).alias("id_agent"),
            coalesce(col("ciq_agents.is_sale_agent"), col("dim_agent.is_sale_agent")).alias("is_sale_agent"),
            coalesce(col("ciq_agents.is_rent_agent"), col("dim_agent.is_rent_agent")).alias("is_rent_agent"),
        )
    )

# COMMAND ----------

# DBTITLE 1,Tickets related to agents
def _tickets_by_user_monthly(load_end_date: str, months_window: int = 18) -> DataFrame:
    """(sk_user, reference_month, total_tickets, sum_reopens, ticket_breakdown_aggregated)."""
    month_start, month_end = _month_range(load_end_date, months_window)
    fact_tickets = spark.table(TABLE_FACT_TICKETS).alias("fact_tickets")
    dim_taxonomy = spark.table(TABLE_DIM_TAXONOMY).alias("dim_taxonomy")
    tickets_with_taxonomy = (
        fact_tickets.join(dim_taxonomy, col("fact_tickets.sk_taxonomy") == col("dim_taxonomy.sk_taxonomy"), "left")
        .filter(
            (col("fact_tickets.sk_user") != -1)
            & (col("fact_tickets.direction") == "inbound")
            & col("fact_tickets.sk_ticket").isNotNull()
        )
        .withColumn(
            "ticket_created_month",
            date_trunc("month", col("fact_tickets.ts_created")),
        )
    )
    tickets_in_window = _filter_in_month_window(
        tickets_with_taxonomy, "ticket_created_month", month_start, month_end
    )
    tickets_with_taxonomy = tickets_in_window.select(
        col("fact_tickets.sk_user").alias("sk_user"),
        col("fact_tickets.sk_ticket"),
        col("fact_tickets.reopens"),
        col("fact_tickets.channel"),
        col("dim_taxonomy.step_tag"),
        col("dim_taxonomy.theme_detail"),
        to_date(date_trunc("month", col("fact_tickets.ts_solved"))).alias("reference_month"),
    )
    tickets_by_channel_step_theme = (
        tickets_with_taxonomy.groupBy("sk_user", "reference_month", "channel", "step_tag", "theme_detail")
        .agg(
            countDistinct("sk_ticket").alias("total_tickets"),
            spark_sum("reopens").alias("sum_reopens"),
        )
    )
    return tickets_by_channel_step_theme.groupBy("sk_user", "reference_month").agg(
        spark_sum("total_tickets").alias("total_tickets"),
        spark_sum("sum_reopens").alias("sum_reopens"),
        collect_list(
            struct(
                col("channel"),
                col("step_tag"),
                col("theme_detail"),
                col("total_tickets"),
                col("sum_reopens"),
            )
        ).alias("ticket_breakdown_aggregated"),
    )

# COMMAND ----------

# DBTITLE 1,Eligibility criterias
def _join_base_with_metrics(
    base: DataFrame,
    qualified: DataFrame,
    listings: DataFrame,
    visits: DataFrame,
    independent: DataFrame,
    context: DataFrame,
    tickets: DataFrame,
) -> DataFrame:
    """Left-join base (agent_status_by_month) with all metric and context tables; returns wide DataFrame."""
    base_with_metrics = (
        base.alias("base")
        .join(
            qualified.alias("qualified"),
            (col("base.id_user") == col("qualified.id_user"))
            & (col("base.reference_month") == col("qualified.reference_month")),
            "left",
        )
        .join(
            listings.alias("listings"),
            (col("base.id_user") == col("listings.id_user"))
            & (col("base.reference_month") == col("listings.reference_month")),
            "left",
        )
        .join(
            visits.alias("visits"),
            (col("base.id_agent") == col("visits.id_agent"))
            & (col("base.reference_month") == col("visits.reference_month")),
            "left",
        )
        .join(
            independent.alias("independent"),
            col("base.id_user") == col("independent.id_user"),
            "left",
        )
        .join(
            context.alias("context"),
            col("base.id_user") == col("context.id_user"),
            "left",
        )
        .join(
            tickets.alias("tickets"),
            (col("base.id_user") == col("tickets.sk_user"))
            & (col("base.reference_month") == col("tickets.reference_month")),
            "left",
        )
    )
    return base_with_metrics.select(
        col("base.id_user"),
        col("base.id_agent"),
        col("base.reference_month"),
        coalesce(col("listings.total_listings_count"), lit(0)).alias("total_listings_count"),
        coalesce(col("visits.total_visits_count"), lit(0)).alias("total_visits_count"),
        col("qualified.id_user").isNotNull().alias("is_ciq_qualified_active"),
        col("independent.is_passive_lead_receiver").alias("is_passive_lead_receiver_current"),
        col("context.is_sale_agent"),
        col("context.is_rent_agent"),
        col("base.agent_status"),
        col("base.ciq_status"),
        col("tickets.total_tickets"),
        col("tickets.sum_reopens"),
        col("tickets.ticket_breakdown_aggregated"),
    )


def _add_eligibility_flags(base_with_metrics: DataFrame) -> DataFrame:
    """
    Add final output columns: identity columns, metrics, and boolean eligibility/activity flags.
    Uses constants for status values and thresholds so rules are easy to read and change.
    """
    agent_status = coalesce(col("agent_status"), lit(AGENT_STATUS_INACTIVE))
    ciq_status = coalesce(col("ciq_status"), lit(AGENT_STATUS_INACTIVE))
    is_passive = coalesce(col("is_passive_lead_receiver_current"), lit(True))

    is_demand_agent_eligible = (agent_status == AGENT_STATUS_ACTIVE)
    is_ciq_eligible = (ciq_status == AGENT_STATUS_ACTIVE)
    is_independent_agent = (
        (is_passive == False)
        & (ciq_status == AGENT_STATUS_ACTIVE)
        & (agent_status == AGENT_STATUS_ACTIVE)
    )
    is_agent_active = (agent_status == AGENT_STATUS_ACTIVE) & (col("total_visits_count") > MIN_VISITS_FOR_ACTIVE_AGENT)
    is_ciq_active = (ciq_status == AGENT_STATUS_ACTIVE) & (col("total_listings_count") > MIN_LISTINGS_FOR_ACTIVE_CIQ)
    is_ineligible = (agent_status == AGENT_STATUS_INACTIVE) & (ciq_status == AGENT_STATUS_INACTIVE)

    return base_with_metrics.select(
        col("id_user"),
        col("id_agent"),
        col("reference_month"),
        col("total_listings_count"),
        col("total_visits_count"),
        col("is_sale_agent"),
        col("is_rent_agent"),
        col("total_tickets"),
        col("sum_reopens"),
        col("ticket_breakdown_aggregated"),
        is_demand_agent_eligible.alias("is_demand_agent_eligible"),
        is_ciq_eligible.alias("is_ciq_eligible"),
        is_independent_agent.alias("is_independent_agent"),
        is_agent_active.alias("is_agent_active"),
        is_ciq_active.alias("is_ciq_active"),
        col("is_ciq_qualified_active"),
        is_ineligible.alias("is_ineligible"),
    )


def build_agent_support_tickets_by_month(args: Namespace) -> DataFrame:
    """
    Build the final agent_support_tickets_by_month: base status + listings, visits, tickets,
    and eligibility/activity flags.
    """
    months_window = int(getattr(args, "months_window", 18))
    month_start, month_end = _month_range(args.load_end_date, months_window)

    status_by_month = spark.table(TABLE_STATUS_BY_MONTH)
    status_by_month_in_window = _filter_in_month_window(
        status_by_month, "reference_month", month_start, month_end
    )

    qualified_ciq_user_months       = _qualified_active_ciqs_by_month(args.load_end_date, months_window)
    listings_count_by_user_month    = _all_listings_by_month(args.load_end_date, months_window)
    visits_count_by_agent_month     = _all_agents_visits_by_month(args.load_end_date, months_window)
    independent_agent_eligibility   = _independent_agent_eligible()
    business_context                = _business_context()
    tickets_by_user_month           = _tickets_by_user_monthly(args.load_end_date, months_window)

    base_with_metrics = _join_base_with_metrics(
        status_by_month_in_window,
        qualified_ciq_user_months,
        listings_count_by_user_month,
        visits_count_by_agent_month,
        independent_agent_eligibility,
        business_context,
        tickets_by_user_month,
    )
    return _add_eligibility_flags(base_with_metrics)

# COMMAND ----------

# DBTITLE 1,Pre-write validations
TICKET_BREAKDOWN_STRUCT = StructType([
    StructField("channel", StringType(), True),
    StructField("step_tag", StringType(), True),
    StructField("theme_detail", StringType(), True),
    StructField("total_tickets", LongType(), True),
    StructField("sum_reopens", LongType(), True),
])

EXPECTED_SCHEMA = StructType([
    StructField("id_user", LongType(), True),
    StructField("id_agent", LongType(), True),
    StructField("reference_month", DateType(), True),
    StructField("total_listings_count", LongType(), False),
    StructField("total_visits_count", LongType(), False),
    StructField("is_sale_agent", BooleanType(), True),
    StructField("is_rent_agent", BooleanType(), True),
    StructField("total_tickets", LongType(), True),
    StructField("sum_reopens", LongType(), True),
    StructField("ticket_breakdown_aggregated", ArrayType(TICKET_BREAKDOWN_STRUCT), True),
    StructField("is_demand_agent_eligible", BooleanType(), False),
    StructField("is_ciq_eligible", BooleanType(), False),
    StructField("is_independent_agent", BooleanType(), False),
    StructField("is_agent_active", BooleanType(), False),
    StructField("is_ciq_active", BooleanType(), False),
    StructField("is_ciq_qualified_active", BooleanType(), False),
    StructField("is_ineligible", BooleanType(), False),
])


def _schema_mismatches(actual: StructType, expected: StructType) -> list[str]:
    actual_by_name = {f.name: f for f in actual.fields}
    expected_by_name = {f.name: f for f in expected.fields}
    mismatch_list = []
    for name in actual_by_name.keys() | expected_by_name.keys():
        if name not in actual_by_name:
            mismatch_list.append(f"missing: {name}")
        elif name not in expected_by_name:
            mismatch_list.append(f"unexpected: {name}")
        elif actual_by_name[name].dataType.simpleString() != expected_by_name[name].dataType.simpleString():
            mismatch_list.append(f"{name}: expected {expected_by_name[name].dataType.simpleString()}, got {actual_by_name[name].dataType.simpleString()}")
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
    """Write DataFrame to enrich layer (Delta merge), refresh table, apply privileges."""
    db_info = DatalakeMetastoreService.get_db_info(
        args.env, args.database_base_name, args.datalake_bucket
    )
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    full_table_name = f"{database_name}.{args.table_name}"
    s3_path = database_location + args.table_name

    SparkMetastoreService(spark_client).create_database(database_name)
    DeltaLoader().load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=result_df,
        partition_by=["reference_month"],
        merge_on=["id_user", "reference_month"],
    )
    SparkMetastoreService(spark_client).refresh_table(database_name, args.table_name)
    priv = TablePrivileges.from_environment_default(full_table_name)
    if priv and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        priv.apply()
    logger.info(f"m=save_df, table={full_table_name}, rows={row_count:,}")


def save_df(
    spark_client: SparkClient, result_df: DataFrame, args: Namespace, row_count: Optional[int] = None
) -> None:
    """Dispatch to dev (temp view) or prod (Delta merge to enrich). row_count from validate_before_write avoids recount in prod."""
    run_mode = getattr(args, "run_mode", "dev")
    if run_mode == "dev":
        view_name = f"dev_{args.table_name}"
        result_df.cache()
        dev_row_count = result_df.count()
        result_df.createOrReplaceTempView(view_name)
        logger.info(
            f"Dev mode: Cached and registered temp view '{view_name}' ({dev_row_count:,} rows)"
            f"({row_count:,} rows). Query in this session with: SELECT * FROM {view_name}"
        )
        return
    elif run_mode == "prod":
        _save_to_enrich(spark_client, result_df, args, row_count if row_count is not None else result_df.count())
    else:
        raise ValueError(f"Invalid run mode: {run_mode}")

# COMMAND ----------

# DBTITLE 1,Main
def main(args: Namespace | None = None) -> None:
    if args is None:
        args = parse_args()
    run_mode = getattr(args, "run_mode", "dev")
    logger.info(
        f"m=main, run_mode={run_mode}, table={args.table_name}, "
        f"interval_end={args.load_end_date}, msg=Starting"
    )
    
    support_tickets_by_month = build_agent_support_tickets_by_month(args)
    row_count = validate_before_write(support_tickets_by_month)
    save_df(SparkClient(), support_tickets_by_month, args, row_count=row_count)
    logger.info("m=main, msg=Job finished successfully")

# COMMAND ----------

if __name__ == "__main__":
    main()
