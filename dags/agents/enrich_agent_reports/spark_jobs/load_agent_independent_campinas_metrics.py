# Databricks notebook source
# DBTITLE 1,Local dev configuration
# MAGIC %run "/Workspace/Data Engineering/Data Partners/1. Utils/templates/local_config"

# COMMAND ----------

# DBTITLE 1,Import libs
from argparse import ArgumentParser, Namespace
from datetime import date, timedelta, datetime
from dateutil.relativedelta import relativedelta
from typing import Optional

from pyspark.sql import DataFrame, Window
from pyspark.sql.functions import (
    add_months,
    coalesce,
    col,
    count,
    date_trunc,
    datediff,
    least,
    lit,
    min as spark_min,
    to_date,
    when,
)
from pyspark.sql.types import (
    BooleanType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger

# COMMAND ----------

# DBTITLE 1,Setup & Constants
JOB_NAME = "load_agent_independent_campinas_metrics"
logger = QuintoAndarLogger(JOB_NAME)

CAMPINAS_CITY_ID = 1
MONTHS_WINDOW_DEFAULT = 2
MAX_REGION_DEPTH = 10

TABLE_STATUS_BY_MONTH   = "datalake_agent_reports.agent_status_by_month"
TABLE_OFFER_SPECIALISTS = "datalake_sale_offer_flows.offer_specialists"
TABLE_CIQ_FIRST_LISTING = "datalake_tiers.ciq_first_listing"
TABLE_PARTNER           = "datalake_ebdb_clean.partner"
TABLE_PARTNER_AGENT     = "datalake_ebdb_clean.partner_agent"
TABLE_AGENT_DATA        = "datalake_ebdb_clean.agent_data"
TABLE_REGION            = "datalake_ebdb_clean.region"
TABLE_AGENT_REGION_DATA = "datalake_ebdb_clean.agent_region_data"

# COMMAND ----------

# DBTITLE 1,Argument parsing
# Order must match DAG spark_job_arguments + extra_spark_job_arguments (load_start_date for alignment).
ARG_SPEC = [
    ("env",                 str, "forno", "Environment: forno/prod"),
    ("datalake_bucket",     str, "5a-datalake-prod", "Datalake bucket"),
    ("database_base_name",  str, "agent_reports", "Base name for database (schema)"),
    ("dag_name",            str, "enrich_agent_reports", "DAG name"),
    ("table_name",          str, "agent_independent_campinas_metrics", "Target enrich table name"),
    ("load_start_date",     str, lambda: (date.today() - timedelta(days=30)).isoformat(), "Interval start (alignment with DAG; window uses load_end_date + months_window)"),
    ("load_end_date",       str, lambda: date.today().isoformat(), "Interval end YYYY-MM-DD (window end)"),
    ("run_mode",            str, "dev", "Run mode: prod/dev"),
    ("months_window",       int, MONTHS_WINDOW_DEFAULT, "Number of months in the lookback window"),
]

def _defaults():
    return [d() if callable(d) else d for _, _, d, _ in ARG_SPEC]

def parse_args() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    default_values = _defaults()
    for (name, type_, _default, help_text), default_val in zip(ARG_SPEC, default_values):
        parser.add_argument(name, nargs="?", type=type_, default=default_val, help=help_text)
    namespace, _ = parser.parse_known_args()
    return namespace

def _month_range(load_end_date: str, months_window: int) -> tuple[date, date]:
    """Return (month_start, month_end) as Python dates for the lookback window."""
    end_date = datetime.strptime(load_end_date, "%Y-%m-%d").date()
    month_end = end_date.replace(day=1)
    month_start = month_end - relativedelta(months=months_window - 1)
    return month_start, month_end



# COMMAND ----------

# DBTITLE 1,TQX first lead referral by user/month
def _tqx_first_date_df(month_start: date, month_end: date) -> DataFrame:
    """First TQX referral date per user and metrics by reference_month (self-referral leads).
    Filtered to reference_month in [month_start, month_end] for incremental merge.
    """
    offer = spark.table(TABLE_OFFER_SPECIALISTS).filter(
        col("id_user_agent_lead_referral") == col("id_user_agent")
    )
    by_month = (
        offer.withColumn(
            "reference_month",
            date_trunc("month", col("ts_agent_lead_referral_updated")),
        )
        .groupBy(col("id_user_agent").alias("id_user"), "reference_month")
        .agg(
            count("id_offer").alias("total_tqx_count"),
            spark_min("ts_agent_lead_referral_updated").alias(
                "ts_first_activation_TQX_referral"
            ),
        )
    )
    window = Window.partitionBy("id_user")
    first_activation = by_month.withColumn(
            "ts_first_activation_TQX_referral",
            spark_min("ts_first_activation_TQX_referral").over(window),
        )

    return (
        first_activation
        .filter(
            (to_date(col("reference_month")) >= lit(month_start))
            & (to_date(col("reference_month")) <= lit(month_end))
        )
    )

# COMMAND ----------

# DBTITLE 1,Valid first listing by user/month
def _valid_first_listing_df(month_start: date, month_end: date) -> DataFrame:
    """First valid listing activation per user and listing count by reference_month.
    Filtered to reference_month in [month_start, month_end] for incremental merge.
    """
    first_listing = (
        spark.table(TABLE_CIQ_FIRST_LISTING)
        .filter(col("is_first_listing_valid") == True)
        .withColumn(
            "reference_month",
            date_trunc("month", col("ts_original_first_listing")),
        )
        .groupBy("id_agent", "id_user", "reference_month")
        .agg(
            count("*").alias("total_listings_count"),
            spark_min("ts_original_first_listing").alias(
                "ts_valid_activation_first_listing"
            ),
        )
    )
    window = Window.partitionBy("id_user")
    first_activation = first_listing.withColumn(
            "ts_valid_activation_first_listing",
            spark_min("ts_valid_activation_first_listing").over(window),
        )


    return (
        first_activation
        .filter(
            (to_date(col("reference_month")) >= lit(month_start))
            & (to_date(col("reference_month")) <= lit(month_end))
        )
    )

# COMMAND ----------

# DBTITLE 1,Campinas region mapping (city + all descendants, recursive)

def _region_subtree_ids(
    region: DataFrame, included_ids: DataFrame, depth: int = 0
) -> DataFrame:
    """
    Recursively expand included_ids with all regions whose id_parent_region is
    already in included_ids. Stops when no new regions are found (fixpoint) or
    max depth is reached (guard against cycles / stack overflow).
    """
    if depth >= MAX_REGION_DEPTH:
        return included_ids
    # Regions whose parent is in the current set (one level down)
    children = (
        region.alias("r")
        .join(
            included_ids.alias("inc"),
            col("r.id_parent_region") == col("inc.region_id"),
        )
        .select(col("r.id").alias("region_id"))
    )
    new_ids = children.alias("chd").join(
        included_ids.alias("inc"),
        col("chd.region_id") == col("inc.region_id"),
        "left_anti",
    )
    if new_ids.count() == 0:
        return included_ids
    expanded = included_ids.union(new_ids).distinct()
    return _region_subtree_ids(region, expanded, depth + 1)


def _resolve_id_original_parent(region: DataFrame) -> DataFrame:
    """
    For each region id, walk up the parent chain until we find level == "Cidade";
    return (region_id, id_original_parent, name_original_parent). Uses iterative
    self-join up to MAX_REGION_DEPTH.
    """
    ancestor = region.select(
        col("id").alias("region_id"),
        col("id_parent_region").alias("current_parent"),
        when(col("level") == "Cidade", col("id")).alias("id_original_parent"),
        when(col("level") == "Cidade", col("name")).alias("name_original_parent"),
    )
    parent_cols = region.select(
        col("id").alias("pid"),
        col("id_parent_region").alias("pid_parent"),
        col("level").alias("parent_level"),
        col("name").alias("parent_name"),
    )
    for _ in range(MAX_REGION_DEPTH - 1):
        ancestor = ancestor.join(parent_cols, col("current_parent") == col("pid"), "left").select(
            col("region_id"),
            coalesce(col("pid_parent"), col("current_parent")).alias("current_parent"),
            coalesce(
                col("id_original_parent"),
                when(col("parent_level") == "Cidade", col("pid")),
            ).alias("id_original_parent"),
            coalesce(
                col("name_original_parent"),
                when(col("parent_level") == "Cidade", col("parent_name")),
            ).alias("name_original_parent"),
        )
    return ancestor.select("region_id", "id_original_parent", "name_original_parent")


def _region_subtree_ids(
    region: DataFrame, included_ids: DataFrame, depth: int = 0
) -> DataFrame:
    """
    Recursively expand included_ids with all regions whose id_parent_region is
    already in included_ids. Stops when no new regions are found (fixpoint) or
    max depth is reached (guard against cycles / stack overflow).
    """
    if depth >= MAX_REGION_DEPTH:
        return included_ids
    # Regions whose parent is in the current set (one level down)
    children = (
        region.alias("r")
        .join(
            included_ids.alias("inc"),
            col("r.id_parent_region") == col("inc.region_id"),
        )
        .select(col("r.id").alias("region_id"))
    )
    new_ids = children.alias("chd").join(
        included_ids.alias("inc"),
        col("chd.region_id") == col("inc.region_id"),
        "left_anti",
    )
    if new_ids.count() == 0:
        return included_ids
    expanded = included_ids.union(new_ids).distinct()
    return _region_subtree_ids(region, expanded, depth + 1)


def _resolve_id_original_parent(region: DataFrame) -> DataFrame:
    """
    For each region id, walk up the parent chain until we find level == "Cidade";
    return (region_id, id_original_parent, name_original_parent). Uses iterative
    self-join up to MAX_REGION_DEPTH.
    """
    ancestor = region.select(
        col("id").alias("region_id"),
        col("id_parent_region").alias("current_parent"),
        when(col("level") == "Cidade", col("id")).alias("id_original_parent"),
        when(col("level") == "Cidade", col("name")).alias("name_original_parent"),
    )
    parent_cols = region.select(
        col("id").alias("pid"),
        col("id_parent_region").alias("pid_parent"),
        col("level").alias("parent_level"),
        col("name").alias("parent_name"),
    )
    for _ in range(MAX_REGION_DEPTH - 1):
        ancestor = ancestor.join(parent_cols, col("current_parent") == col("pid"), "left").select(
            col("region_id"),
            coalesce(col("pid_parent"), col("current_parent")).alias("current_parent"),
            coalesce(
                col("id_original_parent"),
                when(col("parent_level") == "Cidade", col("pid")),
            ).alias("id_original_parent"),
            coalesce(
                col("name_original_parent"),
                when(col("parent_level") == "Cidade", col("parent_name")),
            ).alias("name_original_parent"),
        )
    return ancestor.select("region_id", "id_original_parent", "name_original_parent")


def _cities_region_mapping(ancestor_ids: Optional[list[int]] = None) -> DataFrame:
    """
    All regions that are cities (level == "Cidade") or descendants of a city,
    with id_original_parent and name_original_parent. Single subtree run for all
    cities, then id/name resolved by walking each region's parent chain.

    Optional ancestor_ids: when provided, filter to rows whose id_original_parent
    is in this list (e.g. [CAMPINAS_CITY_ID] for Campinas-only).
    """
    region = spark.table(TABLE_REGION)
    root_ids = region.filter(col("level") == "Cidade").select(
        col("id").alias("region_id")
    )
    included_ids = _region_subtree_ids(region, root_ids)

    mapping = (
        region.alias("r")
        .join(included_ids.alias("inc"), col("r.id") == col("inc.region_id"))
        .select(
            col("r.id"),
            col("r.id_parent_region"),
            col("r.name"),
            col("r.slug"),
            col("r.level"),
            col("r.id_state"),
            col("r.lat"),
            col("r.lng"),
        )
    )
    region_to_city = _resolve_id_original_parent(region)
    result = mapping.join(
        region_to_city,
        col("id") == col("region_id"),
        "left",
    ).select(
        col("id"),
        col("id_parent_region"),
        col("name"),
        col("slug"),
        col("level"),
        col("id_state"),
        col("lat"),
        col("lng"),
        col("id_original_parent"),
        col("name_original_parent"),
    )
    if ancestor_ids is not None:
        result = result.filter(col("id_original_parent").isin(ancestor_ids))
    return result


def _campinas_agents_df(region_mapping: DataFrame) -> DataFrame:
    """Distinct id_agent_data (id_agent) for agents linked to Campinas regions."""
    return (
        spark.table(TABLE_AGENT_REGION_DATA)
        .join(
            region_mapping.select(col("id").alias("region_id")),
            col("id_regions") == col("region_id"),
        )
        .select(col("id_agent_data").alias("id_agent"))
        .distinct()
    )

# COMMAND ----------

# DBTITLE 1,Main builder
def build_agent_independent_campinas_metrics(args: Namespace) -> DataFrame:
    """
    Build agent-independent Campinas metrics: status by month for Campinas agents,
    joined with TQX referral, first listing, agent_data and partner_agent; add derived flags.
    """
    months_window = int(getattr(args, "months_window", MONTHS_WINDOW_DEFAULT))
    month_start, month_end = _month_range(args.load_end_date, months_window)

    status = (
        spark.table(TABLE_STATUS_BY_MONTH)
        .filter(
            (to_date(col("reference_month")) >= lit(month_start))
            & (to_date(col("reference_month")) <= lit(month_end))
        )
    )
    tqx             = _tqx_first_date_df(month_start, month_end)
    first_listing   = _valid_first_listing_df(month_start, month_end)
    region_mapping  = _cities_region_mapping(ancestor_ids=[CAMPINAS_CITY_ID])
    campinas_agents = _campinas_agents_df(region_mapping)

    agent_data = spark.table(TABLE_AGENT_DATA).select(
        col("id").alias("ad_id"),
        col("ts_created").alias("ts_agent_created"),
    )
    partner_agent = spark.table(TABLE_PARTNER_AGENT).select(
        col("id_user").alias("pa_id_user"),
        col("ts_created").alias("ts_ciq_created"),
    )

    main = (
        status.alias("s")
        .join(campinas_agents.alias("ca"), col("s.id_agent") == col("ca.id_agent"), "inner")
        .join(agent_data, col("s.id_agent") == col("ad_id"), "left")
        .join(
            partner_agent,
            col("s.id_user") == col("pa_id_user"),
            "left",
        )
        .join(
            tqx.alias("tqx"),
            (col("s.id_user") == col("tqx.id_user"))
            & (col("s.reference_month") == col("tqx.reference_month")),
            "left",
        )
        .join(
            first_listing.alias("vfl"),
            (col("s.id_user") == col("vfl.id_user"))
            & (col("s.reference_month") == col("vfl.reference_month")),
            "left",
        )
    )

    result = main.select(
        col("s.id_user"),
        col("s.id_agent"),
        col("s.reference_month"),
        col("s.ciq_status"),
        col("s.agent_status"),
        col("s.is_passive_lead_receiver"),
        col("ts_agent_created"),
        col("ts_ciq_created"),
        col("tqx.ts_first_activation_TQX_referral"),
        coalesce(col("tqx.total_tqx_count"), lit(0)).alias("total_tqx_count"),
        col("vfl.ts_valid_activation_first_listing"),
        coalesce(col("vfl.total_listings_count"), lit(0)).alias("total_listings_count"),
    ).withColumn(
        "is_ciq_active_in_month",
        coalesce(col("total_listings_count"), lit(0)) > 0,
    ).withColumn(
        "is_tqx_active_in_month",
        coalesce(col("total_tqx_count"), lit(0)) > 0,
    ).withColumn(
        "is_ciq_only",
        (col("ciq_status") == "ACTIVE") & (col("agent_status") == "INACTIVE"),
    ).withColumn(
        "is_independent_agent",
        (col("ciq_status") == "ACTIVE")
        & (col("agent_status") == "ACTIVE")
        & (col("is_passive_lead_receiver") == False),
    ).withColumn(
        "days_since_agent_created",
        datediff(col("reference_month"), least(col("ts_agent_created"), col("ts_ciq_created")))
    )

    return result



# COMMAND ----------

# DBTITLE 1,Pre-write checks
def validate_before_write(df: DataFrame) -> int:
    row_count = df.count()
    if row_count == 0:
        raise ValueError("Dataset is empty; aborting write.")
    logger.info(f"m=validate_before_write, rows={row_count:,}")
    return row_count


def _save_to_enrich(
    spark_client: SparkClient, result_df: DataFrame, args: Namespace, row_count: int
) -> None:
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
def main(args: Namespace | None = None) -> None:
    if args is None:
        args = parse_args()
    logger.info(
        f"m=main, run_mode={args.run_mode}, table={args.table_name}, "
        f"load_end_date={args.load_end_date}, months_window={args.months_window}"
    )
    df = build_agent_independent_campinas_metrics(args)
    row_count = validate_before_write(df)
    save_df(SparkClient(), df, args, row_count=row_count)
    logger.info("m=main, msg=Job finished successfully")


if __name__ == "__main__":
    main()
