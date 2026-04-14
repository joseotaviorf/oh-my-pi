from argparse import ArgumentParser
from datetime import date, timedelta
from typing import Optional

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql import types as T
from pyspark.sql.window import Window

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "interaction_state_tracker"
logger = QuintoAndarLogger(JOB_NAME)

METADATA_SCHEMA = T.StructType(
    [
        T.StructField("token_usage", T.MapType(T.StringType(), T.LongType())),
        T.StructField("session_id", T.LongType()),
        T.StructField("calculator_p70_price", T.LongType()),
        T.StructField("sale_price", T.LongType()),
        T.StructField("rent_price", T.LongType()),
        T.StructField("calculator_p90_price", T.LongType()),
        T.StructField("user_id", T.StringType()),
        T.StructField("house_id", T.StringType()),
        T.StructField("business_context", T.StringType()),
        T.StructField("house_ownership", T.StringType()),
        T.StructField("first_message_ts", T.TimestampType()),
    ]
)

HSM_DETAILED_COUNT_SCHEMA = T.MapType(T.StringType(), T.LongType())

EXPECTED_SCHEMA = T.StructType(
    [
        T.StructField("business_context", T.StringType(), True),
        T.StructField("id_house", T.StringType(), True),
        T.StructField("id_user", T.StringType(), True),
        T.StructField("house_ownership", T.StringType(), True),
        T.StructField("sale_price", T.LongType(), True),
        T.StructField("calculator_p70_price", T.LongType(), True),
        T.StructField("rent_price", T.LongType(), True),
        T.StructField("calculator_p90_price", T.LongType(), True),
        T.StructField("interaction_state", T.StringType(), True),
        T.StructField("dt_state", T.DateType(), True),
        T.StructField("hsm_count", T.LongType(), True),
        T.StructField("hsm_detailed_count", T.MapType(T.StringType(), T.LongType()), True),
    ]
)


def _build_langfuse_classifications(load_start_date: str) -> DataFrame:
    """Parse Langfuse PricingStateClassification scores for the given date."""
    return (
        spark.table("datalake_langfuse_clean.scores")  # noqa: F821
        .filter(
            F.make_date(F.col("year"), F.col("month"), F.col("day"))
            == F.lit(load_start_date).cast(T.DateType())
        )
        .filter(F.col("name") == "PricingStateClassification")
        .withColumn("metadata", F.from_json(F.col("metadata"), METADATA_SCHEMA))
        .select(
            F.col("string_value").alias("fup_class"),
            F.col("metadata").getField("session_id").alias("id_session"),
            F.col("metadata").getField("user_id").alias("id_user"),
            F.col("metadata").getField("house_id").alias("id_house"),
            F.col("metadata").getField("business_context").alias("business_context"),
            F.col("metadata").getField("house_ownership").alias("house_ownership"),
            F.col("metadata").getField("first_message_ts").alias("first_message_ts"),
            F.col("metadata").getField("token_usage").alias("token_usage"),
            F.col("metadata").getField("calculator_p70_price").alias("calculator_p70_price"),
            F.col("metadata").getField("sale_price").alias("sale_price"),
            F.col("metadata").getField("rent_price").alias("rent_price"),
            F.col("metadata").getField("calculator_p90_price").alias("calculator_p90_price"),
        )
    )


def _keep_most_recent_session(classification_df: DataFrame) -> DataFrame:
    """When multiple sessions exist per (business_context, id_user, id_house), keep the most recent."""
    window = Window.partitionBy("business_context", "id_user", "id_house").orderBy(
        F.col("first_message_ts").desc()
    )
    return (
        classification_df.withColumn("_row_num", F.row_number().over(window))
        .filter(F.col("_row_num") == 1)
        .drop("_row_num")
    )


def _build_hsm_counts(load_start_date: str) -> DataFrame:
    """Build WhatsApp HSM message counts per (business_context, id_house, id_user).

    Unity Catalog namespace (quintoandar_{env}) is resolved at cluster level via
    spark.databricks.sql.initial.catalog.namespace — 2-part table names are sufficient.
    """
    hsm_messages_df = (
        spark.table("datalake_copilot_service_clean.message")  # noqa: F821
        .filter(F.col("ts_created").cast("date") <= F.lit(load_start_date))
        .filter(F.col("channel") == "WHATSAPP_PRICING_AI_CHAT")
        .filter(F.col("role") == "HARDCODED")
        .select(F.col("id").alias("id_message"), "id_session", "message_index", "role", "content")
        .dropDuplicates()
    )

    message_state_df = spark.table("datalake_copilot_service_clean.state").select(  # noqa: F821
        "id_session",
        "id_message",
        F.get_json_object(F.col("state"), "$.payload.userId").alias("id_user"),
        F.get_json_object(F.col("state"), "$.payload.metadata.houseId").alias("id_house"),
        F.get_json_object(F.col("state"), "$.payload.metadata.businessContext").alias("business_context"),
        F.get_json_object(F.col("state"), "$.ruleId").alias("last_template"),
    )

    hsm_joined_df = hsm_messages_df.join(
        message_state_df, on=["id_session", "id_message"], how="left"
    ).dropDuplicates()

    templates = [
        t.asDict()["last_template"]
        for t in hsm_joined_df.select("last_template").distinct().collect()
    ]

    hsm_detailed_count_df = (
        hsm_joined_df.filter(F.col("message_index") == 0)
        .groupBy("business_context", "id_house", "id_user")
        .pivot("last_template")
        .count()
        .select(
            "business_context",
            "id_house",
            "id_user",
            F.from_json(
                F.to_json(F.struct(*[F.coalesce(F.col(t), F.lit(0)).alias(t) for t in templates])),
                HSM_DETAILED_COUNT_SCHEMA,
            ).alias("hsm_detailed_count"),
        )
    )

    hsm_count_df = (
        hsm_joined_df.filter(F.col("role") == "HARDCODED")
        .groupBy("business_context", "id_user", "id_house")
        .count()
        .withColumnRenamed("count", "hsm_count")
    )

    return hsm_count_df.join(
        hsm_detailed_count_df, on=["business_context", "id_house", "id_user"]
    )


def build_interaction_state(load_start_date: str) -> DataFrame:
    """Build pricing agent interaction state per (business_context, id_house, id_user).

    Sources: Langfuse classifications (scores table) joined with WhatsApp HSM message counts.
    ASP-allocated houses are excluded via left-anti join.
    """
    classification_df = _keep_most_recent_session(
        _build_langfuse_classifications(load_start_date)
    )

    fup_state_df = classification_df.select(
        "id_house",
        "id_user",
        "business_context",
        F.col("fup_class").alias("interaction_state"),
        "house_ownership",
        "sale_price",
        "calculator_p70_price",
        "rent_price",
        "calculator_p90_price",
        F.col("first_message_ts").cast("date").alias("dt_state"),
    ).join(_build_hsm_counts(load_start_date), how="left", on=["business_context", "id_house", "id_user"])

    asp_allocation_df = spark.table("datalake_gsheets_clean.asp_for_sale_alocated")  # noqa: F821
    return fup_state_df.join(asp_allocation_df.select("id_house"), on=["id_house"], how="leftanti")


def _schema_mismatches(actual: T.StructType, expected: T.StructType) -> list:
    """Return list of mismatch messages between actual and expected schema (single pass)."""
    actual_by_name = {f.name: f for f in actual.fields}
    expected_by_name = {f.name: f for f in expected.fields}

    def msg(n):
        if n not in actual_by_name:
            return f"missing column: {n} (expected {expected_by_name[n].dataType.simpleString()})"
        if n not in expected_by_name:
            return f"unexpected column: {n}"
        if actual_by_name[n].dataType.simpleString() != expected_by_name[n].dataType.simpleString():
            return (
                f"column '{n}': expected {expected_by_name[n].dataType.simpleString()}, "
                f"got {actual_by_name[n].dataType.simpleString()}"
            )
        return None

    return list(filter(None, (msg(n) for n in actual_by_name.keys() | expected_by_name.keys())))


def validate_schema_and_return_row_count(df: DataFrame) -> int:
    """Validate schema and return row count. Returns 0 when empty (caller should skip write)."""
    if df.isEmpty():
        logger.warning("m=validate_before_write, msg=Dataset is empty; skipping write.")
        return 0

    mismatches = _schema_mismatches(df.schema, EXPECTED_SCHEMA)
    if mismatches:
        raise ValueError(
            f"Schema mismatch: {'; '.join(mismatches)}. Expected schema: {EXPECTED_SCHEMA.simpleString()}."
        )

    row_count = df.count()
    logger.info(f"m=validate_before_write, rows={row_count:,}, msg=Pre-write checks OK, schema match")
    return row_count


def save_to_enrich(
    spark_client: SparkClient, 
    result_df: DataFrame, 
    env: str, 
    datalake_bucket: str, 
    database_base_name: str, 
    table_name: str, 
    row_count: int,
) -> None:
    """Write DataFrame to enrich layer (Delta merge), refresh table, apply privileges."""
    db_info = DatalakeMetastoreService.get_db_info(
        env, database_base_name, datalake_bucket
    )
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    full_table_name = f"{database_name}.{table_name}"
    s3_path = f"{database_location}{table_name}"

    SparkMetastoreService(spark_client).create_database(database_name)
    DeltaLoader().load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=result_df,
        partition_by=[],
        merge_on=["business_context", "id_house", "id_user"],
    )
    SparkMetastoreService(spark_client).refresh_table(database_name, table_name)
    priv = TablePrivileges.from_environment_default(full_table_name)
    if priv and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        priv.apply()
    logger.info(f"m=save_df, table={full_table_name}, rows={row_count:,}")



if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", default="forno", choices=["forno", "prod"])
    parser.add_argument("bucket", default="5a-datalake-prod")
    parser.add_argument("schema", default="pricing_agent")
    parser.add_argument("dag_name", default="enrich_pricing_agent")
    parser.add_argument("table_name", default="interaction_state_tracker")
    parser.add_argument(
        "load_start_date",
        default=(date.today() - timedelta(days=1)).isoformat(),
    )

    args = parser.parse_args()
    env = args.environment
    datalake_bucket = args.bucket
    database_base_name = args.schema
    dag_name = args.dag_name
    table_name = args.table_name
    load_start_date = args.load_start_date

    logger.info(
        f"m=main, env={env}, database_base_name={database_base_name}, "
        f"dag_name={dag_name}, table_name={table_name}, load_start_date={load_start_date}, "
        f"msg=Starting Spark job"
    )

    output_df = build_interaction_state(load_start_date)
    row_count = validate_schema_and_return_row_count(output_df)
    if row_count == 0:
        logger.info("m=main, msg=Empty dataset — no write performed, job finished successfully")
    else:
        save_to_enrich(
            SparkClient(), 
            output_df, 
            env, 
            datalake_bucket, 
            database_base_name, 
            table_name, 
            row_count
        )
        logger.info("m=main, msg=Job finished successfully")
