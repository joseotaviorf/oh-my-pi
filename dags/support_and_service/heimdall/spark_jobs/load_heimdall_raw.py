import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.clients.db_clients import SparkClient, MongoClient
from bietlejuice.consumers.db_consumers import MongoConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_heimdall_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_details")
    parser.add_argument("raw_table_name")
    parser.add_argument("partition_cols")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_details = json.loads(args.table_details)
    raw_table_name = args.raw_table_name
    partition_cols = json.loads(args.partition_cols)
    execution_date = args.execution_date

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    connection_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.HEIMDALL
    )
    connection = json.loads(connection_json)
    mongo_client = MongoClient(connection)
    spark_client = SparkClient()

    mongo_consumer = MongoConsumer(mongo_client, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    is_incremental = table_details["is_incremental"]

    if is_incremental:
        date_column = table_details["date_column"]

        df = mongo_consumer.get_incremental_data_from_table(
            raw_table_name, date_column, execution_date
        )
    else:
        df = mongo_consumer.get_data_from_table(raw_table_name)

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{raw_table_name}",
        format_options=format_options,
        partitions=partition_cols if is_incremental else None,
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=raw_table_name,
        format_options=format_options,
        force_recreate=False,
        database_location=database_location,
        partitions=partition_cols if is_incremental else None,
    )

    if is_incremental:
        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=raw_table_name,
            df=df,
            partition_cols=partition_cols,
        )
