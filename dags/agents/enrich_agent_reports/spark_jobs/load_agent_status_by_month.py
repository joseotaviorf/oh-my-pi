# Databricks notebook source
# DBTITLE 1,Local dev configuration
# MAGIC %run "/Workspace/Data Engineering/Data Partners/1. Utils/templates/local_config"

# COMMAND ----------

# DBTITLE 1,Import Libs
import inspect
import os
from argparse import ArgumentParser, Namespace
from datetime import date, timedelta

from pyspark.sql import Column, DataFrame, Window
from pyspark.sql.types import (
    BooleanType,
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
# Order must match DAG spark_job_arguments: environment, bucket, schema, dag_name, table_name, data_interval_start, data_interval_end.
# (name, type, default_for_dev, help_text). Default can be a callable for runtime values (e.g. today).
ARG_SPEC = [
    ("env", str, "forno", "Environment: forno/prod"),
    ("datalake_bucket", str, "5a-datalake-prod", "Datalake bucket"),
    ("database_base_name", str, "agent_reports", "Base name for database (schema)"),
    ("dag_name", str, "enrich_agent_reports", "DAG name (for alignment with Airflow)"),
    ("table_name", str, "agent_status_by_month", "Target enrich table name"),
    ("data_interval_start", str, lambda: (date.today() - timedelta(days=7)).isoformat(), "Date interval start, format %Y-%m-%d"),
    ("data_interval_end", str, lambda: date.today().isoformat(), "Date interval end, format %Y-%m-%d"),
]


def parse_args() -> Namespace:
    """Parse arguments passed to the job (align with DAG spark_job_arguments)."""
    parser = ArgumentParser(description=JOB_NAME)
    for name, type_, _default, help_text in ARG_SPEC:
        parser.add_argument(name, type=type_, help=help_text)
    return parser.parse_args()

def _resolve_defaults():
    return [d() if callable(d) else d for _, _, d, _ in ARG_SPEC]

def get_args() -> Namespace:
    """run_mode=prod → parse_args(). run_mode=dev → widgets or env/defaults from ARG_SPEC."""
    run_mode = (os.environ.get("RUN_MODE") or "").strip().lower() or "dev"
    if run_mode == "prod":
        args = parse_args()
        args.run_mode = "prod"
        return args
    if run_mode == "dev":
        defaults = _resolve_defaults()
        defaults_str = [str(d) for d in defaults]
        dbutils = None
        try:
            f = inspect.currentframe()
            if f and f.f_back:
                dbutils = f.f_back.f_globals.get("dbutils")
        except Exception:
            pass
        if dbutils:
            for (name, _, _, _), default in zip(ARG_SPEC, defaults_str):
                try:
                    dbutils.widgets.drop(name)
                except Exception:
                    pass
                dbutils.widgets.text(name, default, name.replace("_", " ").title())
            values = {name: dbutils.widgets.get(name).strip() for name, _, _, _ in ARG_SPEC}
        else:
            values = dict(zip([name for name, _, _, _ in ARG_SPEC], defaults_str))
        return Namespace(run_mode="dev", **values)
    raise ValueError(f"RUN_MODE must be 'dev' or 'prod', got: {run_mode!r}")

# COMMAND ----------

# DBTITLE 1,Expand dataframe by month
def _expand_status_by_month(
    df: DataFrame,
    data_interval_start: str,
    data_interval_end: str,
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

    month_start = date_trunc("month", to_date(lit(data_interval_start)))
    month_end = last_day(to_date(lit(data_interval_end)))

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
    result = selected.drop("rn", "_month_start", "_month_end").withColumnRenamed(
        "month_ref", "reference_month"
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
    data_interval_start: str,
    data_interval_end: str,
) -> DataFrame:
    """CIQ path: ciq_users -> expand by month -> one row per (id_user, reference_month) with ciq_* columns."""
    ciq = (
        spark.table("datalake_ebdb_agents.ciq_users")
        .filter(col("ts_agent_status_start").isNotNull())
    )
    expanded = _expand_status_by_month(
        ciq,
        data_interval_start,
        data_interval_end,
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
    )

# COMMAND ----------

# DBTITLE 1,Agent by Month
def _build_agents_status_by_month(
    data_interval_start: str,
    data_interval_end: str,
) -> DataFrame:
    """Agents (Demand) path: audit events -> status periods -> expand by month -> one row per (id_user, reference_month) with agent_* columns."""
    aud = spark.table("datalake_ebdb_clean.agent_data_aud")
    usr = spark.table("datalake_ebdb_user.user")
    ag = spark.table("datalake_ebdb_clean.agent_data")
    # Filter audit to months of interest (include previous month so status at window start is correct)
    month_start = add_months(to_date(lit(data_interval_start)), -1)
    month_end = last_day(to_date(lit(data_interval_end)))
    events = (
        aud.alias("a")
        .join(usr.alias("u"), col("a.id") == col("u.id_agent"), "left")
        .join(ag.alias("g"), col("a.id") == col("g.id"), "left")
        .filter(
            col("a.ts_database_transaction").isNotNull()
            & (col("a.ts_database_transaction") >= month_start)
            & (col("a.ts_database_transaction") <= month_end)
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
        data_interval_start,
        data_interval_end,
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
    )

# COMMAND ----------

# DBTITLE 1,Build all agent status
def build_agents_status(
    data_interval_start: str,
    data_interval_end: str,
) -> DataFrame:
    """
    Build agents status by month: CIQ + agents status by month.
    Splits CIQ and agents expansion, then joins on (id_user, reference_month).
    """
    ciq_monthly = _build_ciq_status_by_month(data_interval_start, data_interval_end)
    agents_monthly = _build_agents_status_by_month(data_interval_start, data_interval_end)
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
        StructField("reference_month", TimestampType(), True),
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


def validate_before_write(df: DataFrame) -> None:
    """Small checks before persisting: not empty and full schema (columns + types). Raises if invalid."""
    row_count = df.count()
    if row_count == 0:
        raise ValueError("Dataset is empty; aborting write.")
    mismatches = _schema_mismatches(df.schema, EXPECTED_SCHEMA)
    if mismatches:
        raise ValueError(
            f"Schema mismatch: {'; '.join(mismatches)}. Expected schema: {EXPECTED_SCHEMA.simpleString()}."
        )
    logger.info(f"m=validate_before_write, rows={row_count:,}, msg=Pre-write checks OK, schema match")


# COMMAND ----------

def save_df(spark_client: SparkClient, df: DataFrame, args: Namespace) -> None:
    """Write DataFrame to enrich layer as Delta. In dev mode uses a session temp view (no S3)."""

    if run_mode == "dev":
        temp_view_name = f"dev_{args.table_name}"
        df.cache()
        row_count = df.count()
        df.createOrReplaceTempView(temp_view_name)
        logger.info(
            f"Dev mode: Cached and registered temp view '{temp_view_name}' "
            f"({row_count:,} rows). Query in this session with: SELECT * FROM {temp_view_name}"
        )
        return

    loader = DeltaLoader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    db_info = DatalakeMetastoreService.get_db_info(
        args.env, args.database_base_name, args.datalake_bucket
    )

    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    s3_path = database_location + args.table_name
    full_table_name = f"{database_name}.{args.table_name}"

    spark_metastore_service.create_database(database_name)

    loader.load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=df,
        partition_by=["reference_month"],
        merge_on=["id_user", "reference_month"],
    )
    spark_metastore_service.refresh_table(database_name, args.table_name)

    table_privileges = TablePrivileges.from_environment_default(full_table_name)
    if table_privileges and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        table_privileges.apply()

    logger.info(f"m=save_df, table={full_table_name}, rows={df.count():,}, msg=Write complete")

# COMMAND ----------

def main(args: Namespace | None = None) -> None:
    """Orchestrate ETL: build -> validate (not empty + schema) -> write."""
    if args is None:
        args = get_args()
    run_mode = getattr(args, "run_mode", "dev")
    logger.info(
        f"m=main, run_mode={run_mode}, env={args.env}, database_base_name={args.database_base_name}, "
        f"table_name={args.table_name}, data_interval=[{args.data_interval_start}, {args.data_interval_end}], msg=Starting Spark job"
    )

    spark_client = SparkClient()
    logger.info(f"m=build_agents_status, data_interval_start={args.data_interval_start}, data_interval_end={args.data_interval_end}, msg=Building CIQ + agents status by month")
    output_dataframe = build_agents_status(
        args.data_interval_start, args.data_interval_end
    )
    validate_before_write(output_dataframe)
    save_df(spark_client, output_dataframe, args)
    logger.info("m=main, msg=Job finished successfully")

# COMMAND ----------

if __name__ == "__main__":
    main()
