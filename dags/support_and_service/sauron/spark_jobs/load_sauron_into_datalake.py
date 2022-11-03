import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_sauron_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    parser.add_argument("source")
    parser.add_argument("tables")
    parser.add_argument("partition_cols")
    parser.add_argument("update_col")
    parser.add_argument("max_records_per_file")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    SOURCE = args.source
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partition_cols = json.loads(args.partition_cols)
    tables = json.loads(args.tables)
    update_col = args.update_col
    max_records_per_file = args.max_records_per_file

    logger.info(
        f"m=__main__, environment={environment}, datalake_bucket={datalake_bucket}, "
        "msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.SAURON)
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    for datalake_table_name, table_info in tables.items():
        sauron_table_name = table_info.get("table_name")
        if table_info.get("partitioned_table"):
            sauron_table_name = sauron_table_name.format(
                year=dt_execution.year, month="{:02d}".format(dt_execution.month)
            )

        df = postgres_consumer.get_incremental_data_from_table(
            sauron_table_name, update_col, execution_date
        )
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{datalake_table_name}",
            format_options=format_options,
            max_records_per_file=max_records_per_file,
            partitions=partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=datalake_table_name,
            format_options=format_options,
            database_location=database_location,
            partitions=partition_cols,
        )

        metastore_service.create_new_partitions_from_df(
            database_name, datalake_table_name, df, partition_cols
        )
