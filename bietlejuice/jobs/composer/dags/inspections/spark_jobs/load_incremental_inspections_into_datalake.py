import json
import logging
from argparse import ArgumentParser

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

JOB_NAME = "load_increental_inspections_into_datalake"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("data_column")
    parser.add_argument("unixtime_measure")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.env
    source = args.source
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    data_column = args.data_column
    unixtime_measure = args.unixtime_measure
    execution_date = args.execution_date

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name}, data_column={data_column}, unixtime_measure={unixtime_measure},
                execution_date={execution_date}, msg=Starting spark job...
        """
    )

    config_service = ConfigurationService(source)
    PARTITIONS = config_service.get_config("partition_columns")

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.INSPECTIONS
        )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    df = postgres_consumer.get_incremental_data_by_granularity_from_table(
         table_name, data_column, execution_date, unixtime_measure=unixtime_measure
    )

    if not df.rdd.isEmpty():
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=PARTITIONS,
        )
        spark_metastore_loader.update_metastore(
            df, 
            database_name,
            table_name, 
            format_options, 
            database_location,
            PARTITIONS,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=PARTITIONS,
        )
    else:
        logger.warning(
            f"""m=__main__, table_name={table_name}, execution_date={execution_date},
            msg=No data returned from Production database."""
        )

