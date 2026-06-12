from argparse import ArgumentParser

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import (
    ArrayType,
    DoubleType,
    StringType,
    StructField,
    StructType,
)
from pyspark.sql.window import Window
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader

JOB_NAME = "load_security_data_gateway_findings_raw"

TABLE_NAME = "security_findings"
DATABASE_NAME = "datalake_security_data_gateway_raw"

MERGE_ON = ["source", "resource_id"]
WHEN_MATCHED_UPDATE_CONDITION = "source.classified_at >= target.classified_at"

# Typed schema for the core FindingEvent fields.
# source_metadata and source_raw_payload are NOT typed here — they are extracted
# as raw JSON strings via get_json_object to preserve arbitrary nested keys and
# tolerate schema evolution without migration.
_FINDING_SCHEMA = StructType(
    [
        StructField("source", StringType(), True),
        StructField("event_type", StringType(), True),
        StructField(
            "resource",
            StructType(
                [
                    StructField("resource_id", StringType(), True),
                    StructField("resource_type", StringType(), True),
                    StructField("resource_name", StringType(), True),
                    StructField("location", StringType(), True),
                ]
            ),
            True,
        ),
        StructField(
            "actor",
            StructType(
                [
                    StructField("email", StringType(), True),
                ]
            ),
            True,
        ),
        StructField(
            "pii_types_detected",
            ArrayType(
                StructType(
                    [
                        StructField("pii_type", StringType(), True),
                        StructField("confidence_score", DoubleType(), True),
                    ]
                )
            ),
            True,
        ),
        StructField("risk_level", StringType(), True),
        StructField("classified_at", StringType(), True),
    ]
)

_REQUIRED_FIELDS = [
    "source",
    "resource_id",
    "event_type",
    "risk_level",
    "classified_at",
]

# Explicit projection — prevents Kafka stream columns (key, value, topic, …) from
# leaking into Delta MERGE via whenMatchedUpdateAll.
_OUTPUT_COLUMNS = [
    "source",
    "event_type",
    "resource_id",
    "resource_type",
    "resource_name",
    "location",
    "actor_email",
    "risk_level",
    "pii_types_detected",
    "source_metadata",
    "source_raw_payload",
    "classified_at",
    "year",
    "month",
    "day",
    "ts_load",
]


def _parse_and_flatten(raw_df: DataFrame) -> DataFrame:
    """Parse Kafka value, flatten scalars, keep nested fields as JSON strings."""
    value_col = F.col("value")

    parsed = raw_df.withColumn("_parsed", F.from_json(value_col, _FINDING_SCHEMA))

    flattened = (
        parsed.withColumn("source", F.col("_parsed.source"))
        .withColumn("event_type", F.col("_parsed.event_type"))
        .withColumn("resource_id", F.col("_parsed.resource.resource_id"))
        .withColumn("resource_type", F.col("_parsed.resource.resource_type"))
        .withColumn("resource_name", F.col("_parsed.resource.resource_name"))
        .withColumn("location", F.col("_parsed.resource.location"))
        .withColumn("actor_email", F.col("_parsed.actor.email"))
        .withColumn("risk_level", F.col("_parsed.risk_level"))
        .withColumn("pii_types_detected", F.col("_parsed.pii_types_detected"))
        # JSON-string extraction for schema-evolution-safe nested fields
        .withColumn(
            "source_metadata", F.get_json_object(value_col, "$.source_metadata")
        )
        .withColumn(
            "source_raw_payload", F.get_json_object(value_col, "$.source_raw_payload")
        )
        # Timestamp + partition columns
        .withColumn("classified_at", F.to_timestamp(F.col("_parsed.classified_at")))
        .withColumn("year", F.year(F.col("classified_at")))
        .withColumn("month", F.month(F.col("classified_at")))
        .withColumn("day", F.dayofmonth(F.col("classified_at")))
        .withColumn("ts_load", F.current_timestamp())
        .drop("_parsed")
    )

    if "offset" in raw_df.columns:
        flattened = flattened.withColumn("_kafka_offset", F.col("offset"))
    if "partition" in raw_df.columns:
        flattened = flattened.withColumn("_kafka_partition", F.col("partition"))

    return flattened


def _filter_invalid_rows(df: DataFrame, dq_counter: dict) -> DataFrame:
    """Drop rows where required fields failed from_json (NULL after parse)."""
    valid_condition = None
    for field in _REQUIRED_FIELDS:
        cond = F.col(field).isNotNull()
        valid_condition = cond if valid_condition is None else (valid_condition & cond)

    # Single-pass count: tag rows then aggregate once to avoid two full scans.
    df_tagged = df.withColumn("_is_valid", valid_condition)
    count_rows = df_tagged.groupBy("_is_valid").count().collect()
    valid_count = sum(r["count"] for r in count_rows if r["_is_valid"])
    invalid_count = sum(r["count"] for r in count_rows if not r["_is_valid"])
    dq_counter["invalid_rows"] = invalid_count
    dq_counter["valid_rows"] = valid_count
    if invalid_count > 0:
        QuintoAndarLogger(JOB_NAME).warning(
            f"m={JOB_NAME}, msg=Filtered {invalid_count} rows failing required-field parse"
        )

    return df_tagged.filter(F.col("_is_valid")).drop("_is_valid")


def _dedupe_batch(df: DataFrame) -> DataFrame:
    """Keep one row per (source, resource_id) — the one with the latest classified_at.

    Delta MERGE raises when multiple source rows match one target row, so this is
    correctness, not an optimisation.

    When classified_at ties within a batch, _kafka_offset (descending) breaks the tie
    so the highest-offset message wins. Offsets are per-partition, so this is not a
    perfect global order across partitions, but it avoids any systematic bias toward
    a specific partition number. source_raw_payload is a final deterministic fallback
    when Kafka metadata is absent (e.g. unit tests).
    """
    order_cols = [F.col("classified_at").desc()]
    if "_kafka_offset" in df.columns:
        order_cols.append(F.col("_kafka_offset").desc())
    order_cols.append(F.col("source_raw_payload").desc_nulls_last())

    window = Window.partitionBy("source", "resource_id").orderBy(*order_cols)
    deduped = (
        df.withColumn("_rn", F.row_number().over(window))
        .filter(F.col("_rn") == 1)
        .drop("_rn")
    )
    for kafka_col in ("_kafka_offset", "_kafka_partition"):
        if kafka_col in deduped.columns:
            deduped = deduped.drop(kafka_col)
    return deduped.select(*_OUTPUT_COLUMNS)


def build_merge_fn(spark, load_path: str, full_table_name: str):
    """Return a foreachBatch function that dedupes + merges + optimizes."""
    delta_loader = DeltaLoader(spark)
    logger = QuintoAndarLogger(JOB_NAME)

    def merge_fn(batch_df: DataFrame, batch_id: int) -> None:
        logger.info(f"m={JOB_NAME}, msg=Processing batch {batch_id}")

        dq_counter: dict = {}
        flattened = _parse_and_flatten(batch_df)
        valid = _filter_invalid_rows(flattened, dq_counter)
        deduped = _dedupe_batch(valid)

        delta_loader.load_table(
            table_name=full_table_name,
            path=load_path,
            source_df=deduped,
            partition_by=["year", "month", "day"],
            merge_on=MERGE_ON,
            when_matched_update_condition=WHEN_MATCHED_UPDATE_CONDITION,
        )

        if dq_counter.get("valid_rows", 0) > 0:
            delta_loader.optimize_table(full_table_name, z_order_by=["resource_id"])

        table_privileges = TablePrivileges.from_environment_default(full_table_name)
        if table_privileges and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
            table_privileges.apply()

        logger.info(
            f"m={JOB_NAME}, batch_id={batch_id}, "
            f"invalid_rows={dq_counter.get('invalid_rows', 0)}, "
            f"msg=Batch complete"
        )

    return merge_fn


class LoadSecurityDataGatewayFindingsRawJob(BaseCoreModelSparkJob):
    def __init__(self):
        super().__init__(JOB_NAME)

    def parse_args(self):
        """Parse argv from LoadCustomTaskCreator spark_job_arguments template."""
        parser = ArgumentParser(description=JOB_NAME)
        parser.add_argument("environment")
        parser.add_argument("bucket")
        parser.add_argument("schema")
        parser.add_argument("partitions")
        parser.add_argument("execution_date")
        add_validation_target_args(parser)
        args = parser.parse_args()
        # BaseCoreModelSparkJob.run() reads dag_name/table_name; fixed for this DAG.
        args.dag_name = "security_data_gateway_findings"
        args.table_name = TABLE_NAME
        return args

    def initialize_spark_session(self):
        session_params = {
            "spark.sql.adaptive.enabled": "true",
            "spark.databricks.delta.retentionDurationCheck.enabled": "false",
            "spark.sql.streaming.schemaInference": "true",
        }
        return SparkClient(session_params=session_params).conn

    def create_core_model(self, spark, args):
        kafka_brokers = self.config_service.get_config("kafka_brokers")
        kafka_topic = self.config_service.get_config("kafka_topic")
        kafka_consumer_group = self.config_service.get_config("kafka_consumer_group")
        kafka_api_key_secret = self.config_service.get_config("kafka_api_key_secret")
        kafka_api_secret_secret = self.config_service.get_config(
            "kafka_api_secret_secret"
        )

        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()
        kafka_api_key = dbutils.secrets.get(
            scope="quintoandar", key=kafka_api_key_secret
        )
        kafka_api_secret = dbutils.secrets.get(
            scope="quintoandar", key=kafka_api_secret_secret
        )

        self.logger.info(
            f"m={JOB_NAME}, msg=Retrieved Kafka credentials, "
            f"key_length={len(kafka_api_key) if kafka_api_key else 0}"
        )

        kafka_options = {
            "kafka.bootstrap.servers": kafka_brokers,
            "subscribe": kafka_topic,
            "kafka.security.protocol": "SASL_SSL",
            "kafka.sasl.mechanism": "PLAIN",
            "kafka.sasl.jaas.config": (
                f"org.apache.kafka.common.security.plain.PlainLoginModule required "
                f'username="{kafka_api_key}" password="{kafka_api_secret}";'
            ),
            "kafka.group.id": kafka_consumer_group,
            "startingOffsets": "earliest",
            "failOnDataLoss": "false",
        }

        return (
            spark.readStream.format("kafka")
            .options(**kafka_options)
            .load()
            .withColumn("value", F.col("value").cast(StringType()))
        )

    def run_pipeline(self, raw_streaming_df, args, spark):
        path_prefix = self.config_service.get_config("path_prefix")
        load_path_suffix = self.config_service.get_config("load_path_suffix")
        prod_location = (
            f"{path_prefix}{args.bucket}{load_path_suffix.rsplit('/', 1)[0]}"
        )
        write_database, write_table, write_location = resolve_datalake_write_target(
            prod_database=DATABASE_NAME,
            prod_table=TABLE_NAME,
            prod_location=prod_location,
            bucket=args.bucket,
            target_database=getattr(args, "target_database_name", None),
            target_table=getattr(args, "target_table_name", None),
        )
        load_path = f"{write_location.rstrip('/')}/{write_table}"
        full_table_name = f"{write_database}.{write_table}"

        checkpoints_path = (
            path_prefix
            + args.bucket
            + self.config_service.get_config("checkpoints_path_suffix")
        )

        merge_fn = build_merge_fn(spark, load_path, full_table_name)

        streaming_query = (
            raw_streaming_df.writeStream.foreachBatch(merge_fn)
            .trigger(availableNow=True)
            .option("checkpointLocation", checkpoints_path)
            .start()
        )

        streaming_query.awaitTermination()

        self.logger.info(f"m={JOB_NAME}, msg=Streaming query completed successfully")


if __name__ == "__main__":
    job = LoadSecurityDataGatewayFindingsRawJob()
    job.run()
