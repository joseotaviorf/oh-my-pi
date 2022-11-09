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
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_quinto_messenger_into_datalake"
SOURCE = "quinto_messenger"

# parameters
config_service = ConfigurationService(SOURCE)
partition_cols = config_service.get_config("partition_cols")
allow_list = config_service.get_config("ALLOW_LIST")
incremental_col = config_service.get_config("incremental_col")
MAX_RECORDS_PER_FILE = config_service.get_config("MAX_RECORDS_PER_FILE")

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date

    logger.info(
        f"m=__main__, environment={environment}, datalake_bucket={datalake_bucket}, "
        "msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.QUINTO_MESSENGER
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    tables = postgres_consumer.get_table_names_and_sizes().collect()
    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    for table in tables:
        if table.table_name in allow_list:
            df = postgres_consumer.get_incremental_data_from_table(
                table.table_name, incremental_col, execution_date
            )
            # the table names in the datalake must be lowercase
            s3_loader.load_df(
                df=df,
                s3_path=f"{database_location}{table.table_name.lower()}",
                format_options=format_options,
                max_records_per_file=MAX_RECORDS_PER_FILE,
                partitions=partition_cols,
            )
            spark_metastore_loader.update_metastore(
                df=df,
                database_name=database_name,
                table_name=table.table_name.lower(),
                format_options=format_options,
                database_location=database_location,
                partitions=partition_cols,
            )
            metastore_service.create_new_partitions_from_df(
                database_name, table.table_name.lower(), df, partition_cols
            )
