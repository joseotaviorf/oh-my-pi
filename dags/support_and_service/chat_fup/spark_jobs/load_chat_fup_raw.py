import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_chat_fup_raw"
SOURCE = "chat_fup"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    parser.add_argument("source")
    parser.add_argument("raw_table_name")
    parser.add_argument("table_info")
    parser.add_argument("partition_cols")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    SOURCE = args.source
    raw_table_name = args.raw_table_name
    table_info = json.loads(args.table_info)
    partition_cols = json.loads(args.partition_cols)

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.CHAT_FUP
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    logger.info(
        "m=__main__, msg=Creating database in Spark Metastore if it doesn't exist..."
    )

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    if table_info.get("partitioned"):
        incremental_col = table_info.get("incremental_col")

        df = postgres_consumer.get_incremental_data_from_table(
            raw_table_name, incremental_col, execution_date
        )
    else:
        df = postgres_consumer.get_data_from_table(raw_table_name)

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{raw_table_name}",
        format_options=format_options,
        partitions=partition_cols if table_info.get("partitioned") else None,
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=raw_table_name,
        format_options=format_options,
        database_location=database_location,
        partitions=partition_cols if table_info.get("partitioned") else None,
    )

    if table_info.get("partitioned"):
        metastore_service.create_new_partitions_from_df(
            database_name, raw_table_name, df, partition_cols
        )
