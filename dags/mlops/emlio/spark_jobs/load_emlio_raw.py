from datetime import datetime
import json
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat

from pyspark.sql.functions import from_json, get_json_object
from pyspark.sql.functions import col, struct
from pyspark.sql.types import StructType, StructField, StringType


JOB_NAME = "load_emlio_raw"

logger = QuintoAndarLogger(JOB_NAME)


def explode_json_column(df, column, json_schema):

    JSON_TYPE_NAMES = ["array", "struct"]
    for field in json_schema:
        if field.dataType.typeName() in JSON_TYPE_NAMES:
            df = df.withColumn(
                field.name,
                from_json(
                    get_json_object(df[column], "$.{}".format(field.name)),
                    schema=field.dataType,
                ),
            )
        else:  # non-collection data types
            df = df.withColumn(
                field.name,
                get_json_object(df[column], "$.{}".format(field.name)).cast(
                    field.dataType
                ),
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
    ]
)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("schema")
    parser.add_argument("partition_cols")
    parser.add_argument("execution_date")
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

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, schema, datalake_bucket
    )

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]

    df = (
        spark_client.conn.readStream.format("kafka")
        .option("kafka.bootstrap.servers", kafka_brokers)
        .option("subscribe", kafka_topic)
        .option("auto.offset.reset", "earliest")
        .option("failOnDataLoss", "false")
        .option("enable.auto.commit", False)
        .load()
    )

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

    spark_metastore_service.create_database(database_name)

    streaming_query = (
        part_df.writeStream.partitionBy(partition_cols)
        .format(load_format)
        .trigger(availableNow=True)
        .option("maxRecordsPerFile", max_records_per_file)
        .option("checkpointLocation", checkpoints_path)
        .outputMode("append")
        .option("path", load_path)
        .toTable(database_name + "." + table_name)
    )

    streaming_query.awaitTermination()

    spark_metastore_service.repair_table_partitions(database_name, table_name)

    spark_metastore_service.refresh_table(database_name, table_name)
