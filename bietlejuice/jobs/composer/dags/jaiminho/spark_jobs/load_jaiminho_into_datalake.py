import json
import logging
from argparse import ArgumentParser
from bietlejuice.jobs.composer.services import configuration_service

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

JOB_NAME = "load_jaiminho_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    parser.add_argument("source")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    source = args.source

    logger.info(
        f"m=__main__, environment={environment}, datalake_bucket={datalake_bucket}, "
        f"execution_date={execution_date} source={source}"
        "msg=Starting spark job..."
    )

    configuration_service = ConfigurationService(source)

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.JAIMINHO
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
    metastore_service.create_database(database_name)
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    partition_cols = configuration_service.get_config("partition_cols")

    tables_config = configuration_service.get_config("tables")
    for table_config in tables_config:
        df = postgres_consumer.get_incremental_data_from_table(
            table_config["table_name"],
            table_config["date_filter_column"],
            execution_date,
        )

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_config['table_name'].lower()}",
            format_options=format_options,
            database_location=database_location,
            partitions=partition_cols,
        )
        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=table_config["table_name"].lower(),
            format_options=format_options,
            database_location=database_location,
            partitions=partition_cols,
        )
        metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=database_name,
            table_name=table_config["table_name"].lower(),
            partition_cols=partition_cols,
        )
