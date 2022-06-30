import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_demand_contact_submission_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("date_filter_column", help="Date filter column")
    parser.add_argument("execution_date", type=str, help="DAG execution date")
    parser.add_argument(
        "unixtime_measure",
        nargs="?",
        default=None,
        type=str,
        help="Unix time measure -> milliseconds, seconds or None",
    )

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    date_filter_column = args.date_filter_column
    execution_date = args.execution_date
    unixtime_measure = args.unixtime_measure

    config_service = ConfigurationService(source)
    partition_cols = config_service.get_config("raw_partition_cols")

    logger.info(
        f"""
        m=__main__, environment={environment}, datalake_bucket={datalake_bucket}, source={source},
        table_name={table_name}, raw_partition_cols={partition_cols}, date_filter_column={date_filter_column},
        execution_date={execution_date}, unixtime_measure={unixtime_measure}, msg=Starting Spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.DEMAND_CONTACT_SUBMISSION
    )

    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()

    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_loader = S3Loader()

    if unixtime_measure is not None:
        df = postgres_consumer.get_incremental_data_by_granularity_from_table(
            table_name, date_filter_column, execution_date, unixtime_measure
        )
    else:
        df = postgres_consumer.get_incremental_data_from_table(
            table_name, date_filter_column, execution_date
        )

    table_name = table_name.lower()

    if not df or df.rdd.isEmpty():
        logger.warning("m=__main__, msg=RDD is empty")
    else:
        logger.info("m=__main__, msg=RDD is not empty. Loading into S3.")

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
        )
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            partition_cols,
            force_recreate=False,
        )
        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=partition_cols,
        )
