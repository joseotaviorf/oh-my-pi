# Databricks notebook source
# DBTITLE 1,Local dev configuration
# MAGIC %run "/Workspace/Data Engineering/Data Partners/1. Utils/templates/local_config"

# COMMAND ----------

# DBTITLE 1,Import Libs
import os
from argparse import ArgumentParser, Namespace
from datetime import date, timedelta
from typing import Optional

from pyspark.sql import Column, DataFrame, Window
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
from pyspark.sql.functions import (
    add_months,
    coalesce,
    col,
    date_trunc,
    explode,
    expr,
    greatest,
    lag,
    last_day,
    lead,
    lit,
    row_number,
    to_date,
    when,
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
JOB_NAME = "agent_status_by_month"
logger = QuintoAndarLogger(JOB_NAME)

# COMMAND ----------

# DBTITLE 1,Argument Parsing (single source of truth: add new args here only)
ARG_SPEC = [
    ("env", str, "forno", "Environment: forno/prod"),
    ("datalake_bucket", str, "5a-datalake-prod", "Datalake bucket"),
    ("database_base_name", str, "agent_reports", "Base name for database (schema)"),
    ("dag_name", str, "enrich_agent_reports", "DAG name (for alignment with Airflow)"),
    ("table_name", str, "agent_status_by_month", "Target enrich table name"),
    ("load_start_date", str, lambda: (date.today() - timedelta(days=7)).isoformat(), "Date interval start, format %Y-%m-%d"),
    ("load_end_date", str, lambda: date.today().isoformat(), "Date interval end, format %Y-%m-%d"),
    ("run_mode", str, "dev", "Run mode: prod/dev"),
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


# COMMAND ----------

# DBTITLE 1,Expand dataframe by month
def _expand_status_by_month(
    df: DataFrame,
    load_start_date: str,
    load_end_date: str,
    ts_start_col: str,
    ts_end_col: str,
    partition_by: list,
    order_by: list,
    order_by_columns: list[str],
) -> DataFrame:
    """Expand status periods by month; add reference_month and days_in_status. Final select: ts_start/end, partition_by, order_by_columns, reference_month, days_in_status.
    Month range: start → first day of month (date_trunc), end → last day of month (last_day), like SQL.
    """
    end_expr = f"coalesce({ts_end_col}, last_day(current_date()))"
    filtered = df.filter(col(ts_start_col).isNotNull())

    month_start = date_trunc("month", to_date(lit(load_start_date)))
    month_end = last_day(to_date(lit(load_end_date)))

    expanded = (
        filtered
        .withColumn("_month_start", month_start)
        .withColumn("_month_end", month_end)
        .withColumn(
            "month_ref",
            explode(
                expr(f"sequence("
                     f"date_trunc('month', {ts_start_col}), "
                     f"date_trunc('month', {end_expr}), "
                     f"interval 1 month)")
            )
        )
        .filter(
            (col("month_ref") >= col("_month_start"))
            & (col("month_ref") <= col("_month_end"))
        )
        .withColumn(
            "days_in_status",
            greatest(
                lit(0),
                expr(f"datediff("
                     f"least(last_day(month_ref), date({end_expr})), "
                     f"greatest(date(month_ref), date({ts_start_col}))) + 1")
            )
        )
    )
    window = Window.partitionBy(*partition_by).orderBy(*order_by)
    ranked = expanded.withColumn("rn", row_number().over(window))
    selected = ranked.filter((col("rn") == 1) & (col("days_in_status") > 0))
    result = (
        selected.drop("rn", "_month_start", "_month_end")
        .withColumn("reference_month", to_date(col("month_ref")))
        .drop("month_ref")
    )

    partition_out = [p if p != "month_ref" else "reference_month" for p in partition_by]
    seen = set()
    final_cols = []
    for c in [ts_start_col, ts_end_col] + partition_out + order_by_columns + ["reference_month", "days_in_status"]:
        if c not in seen and c in result.columns:
            seen.add(c)
            final_cols.append(c)
    return result.select(final_cols)

# COMMAND ----------

# DBTITLE 1,CIQ by Month
def _build_ciq_status_by_month(
    load_start_date: str,
    load_end_date: str,
) -> DataFrame:
    """CIQ path: ciq_users -> expand by month -> one row per (id_user, reference_month) with ciq_* columns."""
    month_start = add_months(to_date(lit(load_start_date)), -1)
    month_end = last_day(to_date(lit(load_end_date)))
    ciq = (
        spark.table("datalake_ebdb_agents.ciq_users")
        .filter(col("ts_agent_status_start").isNotNull())
    )
    expanded = _expand_status_by_month(
        ciq,
        load_start_date,
        load_end_date,
        "ts_agent_status_start",
        "ts_agent_status_end",
        partition_by=["id_user", "month_ref"],
        order_by=[col("days_in_status").desc(), col("status")],
        order_by_columns=["days_in_status", "status"],
    )
    return (
        expanded.withColumn("id_agent", lit(None).cast("bigint"))
        .select(
            col("id_user"),
            col("id_agent"),
            col("status").alias("ciq_status"),
            col("ts_agent_status_start").alias("ciq_status_start"),
            col("ts_agent_status_end").alias("ciq_status_end"),
            col("reference_month"),
            col("days_in_status").alias("ciq_days_in_status"),
        )
    ).filter(
        (col("reference_month") >= month_start)
        & (col("reference_month") <= month_end)
        )

# COMMAND ----------

# DBTITLE 1,Agent by Month
def _build_agents_status_by_month(
    load_start_date: str,
    load_end_date: str,
) -> DataFrame:
    """Agents (Demand) path: audit events -> status periods -> expand by month -> one row per (id_user, reference_month) with agent_* columns."""
    aud = spark.table("datalake_ebdb_clean.agent_data_aud")
    usr = spark.table("datalake_ebdb_user.user")
    ag = spark.table("datalake_ebdb_clean.agent_data")
    # Filter audit to months of interest (include previous month so status at window start is correct)
    month_start = add_months(to_date(lit(load_start_date)), -1)
    month_end = last_day(to_date(lit(load_end_date)))
    events = (
        aud.alias("a")
        .join(usr.alias("u"), col("a.id") == col("u.id_agent"), "left")
        .join(ag.alias("g"), col("a.id") == col("g.id"), "left")
        .filter(
            col("a.ts_database_transaction").isNotNull()
            & (col("g.agent_type") == "CORRETOR_5A")
            & (col("u.id") != -1)
        )
        .select(
            col("a.id").alias("id_agent"),
            col("u.id").alias("id_user"),
            col("a.is_active"),
            col("a.is_passive_lead_receiver"),
            col("a.ts_database_transaction"),
        )
    )
    w_aud = Window.partitionBy("id_agent").orderBy("ts_database_transaction")
    events = events.withColumn("prev_active", lag("is_active").over(w_aud)).withColumn(
        "prev_passive", lag("is_passive_lead_receiver").over(w_aud)
    )
    status_changed = (
        events.filter(
            col("prev_active").isNull()
            | (coalesce(col("prev_active").cast("string"), lit("unknown"))
              != coalesce(col("is_active").cast("string"), lit("unknown")))
            | (coalesce(col("prev_passive").cast("string"), lit("unknown"))
              != coalesce(col("is_passive_lead_receiver").cast("string"), lit("unknown")))
        )
        .withColumn("status", when(col("is_active"), lit("ACTIVE")).otherwise(lit("INACTIVE")))
        .withColumn(
            "ts_agent_status_end",
            lead("ts_database_transaction").over(Window.partitionBy("id_user").orderBy("ts_database_transaction")),
        )
        .select(
            col("id_user"),
            col("id_agent"),
            col("status"),
            col("is_passive_lead_receiver"),
            col("ts_database_transaction").alias("ts_agent_status_start"),
            col("ts_agent_status_end"),
        )
    )
    expanded = _expand_status_by_month(
        status_changed,
        load_start_date,
        load_end_date,
        "ts_agent_status_start",
        "ts_agent_status_end",
        partition_by=["id_user", "month_ref"],
        order_by=[col("days_in_status").desc(), col("status"), col("is_passive_lead_receiver"), col("id_agent")],
        order_by_columns=["days_in_status", "status", "is_passive_lead_receiver", "id_agent"],
    )
    return expanded.select(
        col("id_user"),
        col("id_agent"),
        col("status").alias("agent_status"),
        col("is_passive_lead_receiver"),
        col("ts_agent_status_start").alias("agent_status_start"),
        col("ts_agent_status_end").alias("agent_status_end"),
        col("reference_month"),
        col("days_in_status").alias("agent_days_in_status"),
    ).filter(
        (col("reference_month") >= month_start)
        & (col("reference_month") <= month_end)
        )

# COMMAND ----------

# DBTITLE 1,Build all agent status
def build_agents_status(
    load_start_date: str,
    load_end_date: str,
) -> DataFrame:
    """
    Build agents status by month: CIQ + agents status by month.
    Splits CIQ and agents expansion, then joins on (id_user, reference_month).
    """
    ciq_monthly = _build_ciq_status_by_month(load_start_date, load_end_date)
    agents_monthly = _build_agents_status_by_month(load_start_date, load_end_date)
    return ciq_monthly.alias("ciq").join(
              agents_monthly.alias("el"),
              (col("ciq.id_user") == col("el.id_user"))
              & (col("ciq.reference_month") == col("el.reference_month")),
              "full_outer",
          ).select(
              coalesce(col("ciq.id_user"), col("el.id_user")).alias("id_user"),
              coalesce(col("ciq.id_agent"), col("el.id_agent")).alias("id_agent"),
              coalesce(col("ciq.reference_month"), col("el.reference_month")).alias("reference_month"),
              col("ciq.ciq_status"),
              col("ciq.ciq_days_in_status"),
              col("ciq.ciq_status_start"),
              col("ciq.ciq_status_end"),
              col("el.agent_status"),
              col("el.is_passive_lead_receiver"),
              col("el.agent_days_in_status"),
              col("el.agent_status_start"),
              col("el.agent_status_end"),
          )


# COMMAND ----------

# DBTITLE 1,Pre-write checks (full DQ runs in data_quality process after write)
EXPECTED_SCHEMA = StructType(
    [
        StructField("id_user", LongType(), True),
        StructField("id_agent", LongType(), True),
        StructField("reference_month", DateType(), True),
        StructField("ciq_status", StringType(), True),
        StructField("ciq_days_in_status", IntegerType(), True),
        StructField("ciq_status_start", TimestampType(), True),
        StructField("ciq_status_end", TimestampType(), True),
        StructField("agent_status", StringType(), True),
        StructField("is_passive_lead_receiver", BooleanType(), True),
        StructField("agent_days_in_status", IntegerType(), True),
        StructField("agent_status_start", TimestampType(), True),
        StructField("agent_status_end", TimestampType(), True),
    ]
)


def _schema_mismatches(actual: StructType, expected: StructType) -> list[str]:
    """Return list of mismatch messages between actual and expected schema (single pass)."""
    actual_by_name = {f.name: f for f in actual.fields}
    expected_by_name = {f.name: f for f in expected.fields}
    def msg(n: str) -> str | None:
        if n not in actual_by_name:
            return f"missing column: {n} (expected {expected_by_name[n].dataType.simpleString()})"
        if n not in expected_by_name:
            return f"unexpected column: {n}"
        if actual_by_name[n].dataType.simpleString() != expected_by_name[n].dataType.simpleString():
            return f"column '{n}': expected {expected_by_name[n].dataType.simpleString()}, got {actual_by_name[n].dataType.simpleString()}"
        return None
    return list(filter(None, (msg(n) for n in actual_by_name.keys() | expected_by_name.keys())))


def validate_before_write(df: DataFrame) -> int:
    """Small checks before persisting: not empty and full schema (columns + types). Returns row count for logging."""
    row_count = df.count()
    if row_count == 0:
        raise ValueError("Dataset is empty; aborting write.")
    mismatches = _schema_mismatches(df.schema, EXPECTED_SCHEMA)
    if mismatches:
        raise ValueError(
            f"Schema mismatch: {'; '.join(mismatches)}. Expected schema: {EXPECTED_SCHEMA.simpleString()}."
        )
    logger.info(f"m=validate_before_write, rows={row_count:,}, msg=Pre-write checks OK, schema match")
    return row_count


# COMMAND ----------

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
            f"Dev mode: Cached and registered temp view '{view_name}' ({dev_row_count:,} rows). "
            f"Query in this session with: SELECT * FROM {view_name}"
        )
        return
    if run_mode == "prod":
        _save_to_enrich(spark_client, result_df, args, row_count if row_count is not None else result_df.count())
        return
    raise ValueError(f"Invalid run mode: {run_mode}")

# COMMAND ----------

def main(args: Namespace | None = None) -> None:
    """Orchestrate ETL: build -> validate (not empty + schema) -> write."""
    if args is None:
        args = parse_args()
    run_mode = getattr(args, "run_mode", "dev")
    logger.info(
        f"m=main, run_mode={run_mode}, env={args.env}, database_base_name={args.database_base_name}, "
        f"table_name={args.table_name}, data_interval=[{args.load_start_date}, {args.load_end_date}], msg=Starting Spark job"
    )

    logger.info(f"m=build_agents_status, load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, msg=Building CIQ + agents status by month")
    output_dataframe = build_agents_status(
        args.load_start_date, args.load_end_date
    )
    row_count = validate_before_write(output_dataframe)
    save_df(SparkClient(), output_dataframe, args, row_count=row_count)
    logger.info("m=main, msg=Job finished successfully")

# COMMAND ----------

if __name__ == "__main__":
    main()
