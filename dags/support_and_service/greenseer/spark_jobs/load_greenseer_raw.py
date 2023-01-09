import json
import logging

from argparse import ArgumentParser
from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_greenseer_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = args.execution_date

    logger.info(
        f""""
        m=load_greenseer_into_datalake, environment={environment}, datalake_bucket={datalake_bucket},
        source={source}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    config_service = ConfigurationService(source)

    allow_list = config_service.get_config("allow_list")
    max_records_per_file = config_service.get_config("max_records_per_file")
    partitioned_by = config_service.get_config("partitioned_by")
    partition_cols = config_service.get_config("partition_cols")

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.GREENSEER
    )
    conn_config = json.loads(conn_config_json)

    spark_client = SparkClient()

    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    tables = postgres_consumer.get_table_names_and_sizes().collect()
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)

    s3_loader = S3Loader()

    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    for table in tables:
        if table.table_name.lower() in allow_list:
            df = postgres_consumer.get_incremental_data_from_table(
                table.table_name, partitioned_by, execution_date
            )

            s3_loader.load_df(
                df=df,
                s3_path=f"{database_location}{table.table_name.lower()}",
                format_options=format_options,
                max_records_per_file=max_records_per_file,
                partitions=partition_cols,
            )

            spark_metastore_loader.update_metastore(
                df=df,
                database_name=database_name,
                table_name=table.table_name.lower(),
                format_options=format_options,
                force_recreate=False,
                database_location=database_location,
                partitions=partition_cols,
            )

            metastore_service.create_new_partitions_from_df(
                database_name=database_name,
                table_name=table.table_name.lower(),
                df=df,
                partition_cols=partition_cols,
            )
