import logging
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql.functions import lit
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

JOB_NAME = "load_crawler_listings_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("context")
    parser.add_argument("table_name")
    parser.add_argument("origin", type=str, help="Name of crawled source")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    context = args.context
    table_name = args.table_name
    origin = args.origin
    execution_date_str = args.execution_date

    config_service = ConfigurationService(
        source, intermediate_path=f"{source}/{context}/spark_jobs"
    )
    source_root_path = config_service.get_config("root_path")
    job_extra_args = config_service.get_config("job_extra_args")
    consumer_extra_args = job_extra_args.get("consumer")
    partitions = config_service.get_config("partition_cols")

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    webhook_key = config_service.get_config("notification_webhooks_keys")[
        "data_quality"
    ]

    gchat_webhook = dbutils.secrets.get(
        scope="quintoandar", key=webhook_key
    )

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, context = {context},datalake_bucket={datalake_bucket}, origin={origin},
                source_root_path={source_root_path}, table_name={table_name}, execution_date={execution_date_str} msg=Starting spark job...
        """
    )

    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    # Initializing clients
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    db_info = DatalakeMetastoreService.get_db_info(
        environment, f"{source}_{context}", datalake_bucket
    )

    path = (
        source_root_path
        + f"origin={origin}/year={execution_date.year}/month={execution_date.month}/day={execution_date.day}/"
    )

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]

    try:
        df = s3_consumer.get_data_from_file(path=path, **consumer_extra_args)
        df = (
            df.withColumn("year", lit(execution_date.year))
            .withColumn("month", lit(execution_date.month))
            .withColumn("day", lit(execution_date.day))
        )
        if origin == "emcasa":
            str_schema = "struct<typename:string,itbi:string,propertydeed:string,propertyregistration:string>"
            df = df.withColumn("metadata", df["metadata"].cast(str_schema))

        spark_metastore_service.create_database(database_name)

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partitions,
        )
    except AnalysisException as e:
        logger.info(
            f"""
            m=__main__, environment={environment}, source={source}, context = {context},datalake_bucket={datalake_bucket}, origin={origin},
            source_root_path={source_root_path}, execution_date={execution_date_str}, msg=An exception occurred, e={e}.
            """
        )
        message_content = f"{origin} crawler s3 folder/file validation failed for date {execution_date_str}\n Error: {e}"
        message = Message(content=message_content, destination=gchat_webhook)
        GChatService.send_message(message)
        df = None

    if df is not None:
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            partitions,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=partitions,
        )
