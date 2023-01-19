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

DATABRICKS_SCOPE = "quintoandar"

JOB_NAME = "load_saruman_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_details")
    parser.add_argument("raw_table_name")
    parser.add_argument("max_records_per_file")
    parser.add_argument("partition_cols")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_details = json.loads(args.table_details)
    raw_table_name = args.raw_table_name
    max_records_per_file = args.max_records_per_file
    partition_cols = json.loads(args.partition_cols)
    execution_date = args.execution_date

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
        execution_date={execution_date}, partition_cols={partition_cols},
        raw_table_name={raw_table_name}"""
        "msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=DatabaseEnum.SARUMAN
    )
    conn_config = json.loads(conn_config_json)

    spark_client = SparkClient()

    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)

    s3_loader = S3Loader()

    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    is_incremental = table_details["is_incremental"]

    if is_incremental:
        date_column = table_details["date_column"]

        df = postgres_consumer.get_incremental_data_from_table(
            raw_table_name, date_column, execution_date
        )
    else:
        df = postgres_consumer.get_data_from_table(raw_table_name)

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{raw_table_name}",
        format_options=format_options,
        max_records_per_file=max_records_per_file,
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
        metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=raw_table_name,
            df=df,
            partition_cols=partition_cols,
        )
