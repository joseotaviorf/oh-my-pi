import json
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql.functions import col, from_json, get_json_object, struct
from pyspark.sql.types import StringType, StructField, StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_emlio_raw"

logger = QuintoAndarLogger(JOB_NAME)


def explode_json_column(df, column, json_schema):

    JSON_TYPE_NAMES = ["array", "struct"]
    for field in json_schema:
        if field.dataType.typeName() in JSON_TYPE_NAMES:
            df = df.withColumn(
                field.name,
                from_json(
                    get_json_object(df[column], f"$.{field.name}"),
                    schema=field.dataType,
                ),
            )
        else:  # non-collection data types
            df = df.withColumn(
                field.name,
                get_json_object(df[column], f"$.{field.name}").cast(field.dataType),
            )
    return df


value_schema = StructType(
    [
        StructField("uuid", StringType(), nullable=True),
        StructField("service_id", StringType(), nullable=True),
        StructField("service_version", StringType(), nullable=True),
        StructField("log_timestamp", StringType(), nullable=True),
        StructField("inference_type", StringType(), nullable=True),
        StructField("service_type", StringType(), nullable=True),
        StructField("inputs", StringType(), nullable=False),
        StructField("outputs", StringType(), nullable=True),
        StructField("keys", StringType(), nullable=True),
        StructField("deployment_info", StringType(), nullable=True),
    ]
)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("schema")
    parser.add_argument("partition_cols")
    parser.add_argument("execution_date")
    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    schema = args.schema
    partition_cols = json.loads(args.partition_cols)
    execution_date = args.execution_date

    table_name = "emlio_logs"

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, schema={schema},
            datalake_bucket={datalake_bucket}, partition_cols={partition_cols},
            msg=Starting spark job..."
        """
    )

    config_service = ConfigurationService("emlio")
    kafka_brokers = config_service.get_config("kafka_brokers")
    kafka_topic = config_service.get_config("kafka_topic")
    load_format = config_service.get_config("load_format")
    checkpoints_path = (
        config_service.get_config("path_prefix")
        + config_service.get_config("datalake_bucket")
        + config_service.get_config("checkpoints_path_suffix")
    )
    load_path = (
        config_service.get_config("path_prefix")
        + config_service.get_config("datalake_bucket")
        + config_service.get_config("load_path_suffix")
    )
    kafka_columns = config_service.get_config("kafka_columns")
    max_records_per_file = config_service.get_config("max_records_per_file")

    session_params = {
        "spark.sql.adaptive.enabled": "true",
        "spark.databricks.delta.retentionDurationCheck.enabled": "false",
        "spark.sql.streaming.schemaInference": "true",
        "spark.sql.streaming.adaptiveQueryExecution.enabled": "true",
    }

    spark_client = SparkClient(session_params=session_params)
    spark_metastore_service = SparkMetastoreService(spark_client)

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, schema, datalake_bucket
    )

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )
    if is_validation_run(args.target_database_name, args.target_table_name):
        load_path = f"{write_location}{write_table_name}"
        checkpoints_path = f"{write_location}{write_table_name}_checkpoints/"

    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()
    kafka_api_key = dbutils.secrets.get(scope="quintoandar", key="EMLIO_KAFKA_API_KEY")
    kafka_api_secret = dbutils.secrets.get(
        scope="quintoandar", key="EMLIO_KAFKA_API_SECRET"
    )

    logger.info(
        f"m={JOB_NAME}, msg=Retrieved Kafka credentials, key_length={len(kafka_api_key) if kafka_api_key else 0}, secret_length={len(kafka_api_secret) if kafka_api_secret else 0}"
    )

    kafka_options = {
        "kafka.bootstrap.servers": kafka_brokers,
        "subscribe": kafka_topic,
        "kafka.security.protocol": "SASL_SSL",
        "kafka.sasl.mechanism": "PLAIN",
        "kafka.sasl.jaas.config": f'org.apache.kafka.common.security.plain.PlainLoginModule required username="{kafka_api_key}" password="{kafka_api_secret}";',
        "kafka.group.id": "emlio",
        "startingOffsets": "earliest",
        "failOnDataLoss": "false",
    }
    df = spark_client.conn.readStream.format("kafka").options(**kafka_options).load()

    raw_df = df.withColumn("key", col("key").cast("string")).withColumn(
        "value", col("value").cast("string")
    )

    emlio_df = raw_df.withColumn("kafka_metadata", struct(kafka_columns))
    emlio_df = explode_json_column(raw_df, column="value", json_schema=value_schema)
    final_df = emlio_df.select([field.name for field in value_schema])

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    part_df = (
        SparkDataFrameService()
        .input(final_df)
        .create_year_month_day_columns_from_date(dt_execution)
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )

    spark_metastore_service.create_database(write_database_name)

    streaming_query = (
        part_df.writeStream.partitionBy(partition_cols)
        .format(load_format)
        .trigger(availableNow=True)
        .option("maxRecordsPerFile", max_records_per_file)
        .option("checkpointLocation", checkpoints_path)
        .option("mergeSchema", "true")
        .outputMode("append")
        .option("path", load_path)
        .toTable(f"{write_database_name}.{write_table_name}")
    )

    streaming_query.awaitTermination()

    spark_metastore_service.repair_table_partitions(
        write_database_name, write_table_name
    )

    spark_metastore_service.refresh_table(write_database_name, write_table_name)
