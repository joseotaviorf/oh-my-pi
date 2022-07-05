import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.pipeline import (
    IncrementalTableLoaderPipeline,
    FullTableLoaderPipeline,
)
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_kodak_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("source", type=str)
    parser.add_argument("table_name", type=str)
    parser.add_argument("execution_date", type=str)
    parser.add_argument("extraction_type", type=str, help="incremental/full")
    parser.add_argument(
        "date_filter_column",
        type=str,
        help="If incremental, filter by this column",
        required=False,
        default=None,
    )

    return parser.parse_args()


def get_conn_config():
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.KODAK)

    return json.loads(conn_config_json)


def main():
    args = parse_arguments()

    config_service = ConfigurationService(args.source)
    partition_cols = config_service.get_config("partition_cols")

    logger.info(
        f"""
        m=__main__, environment={args.env}, source={args.source}, datalake_bucket={args.datalake_bucket},
        execution_date={args.execution_date}, table_name={args.table_name}, extraction_type={args.extraction_type},
        date_filter_column={args.date_filter_column}, msg=Starting spark job...
        """
    )

    conn_config = get_conn_config()
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    db_info = DatalakeMetastoreService.get_db_info(
        args.env, args.source, args.datalake_bucket
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    if args.extraction_type == "incremental":
        df = postgres_consumer.get_incremental_data_from_table(
            args.table_name, args.date_filter_column, args.execution_date
        )
        IncrementalTableLoaderPipeline(
            database_name,
            args.table_name,
            database_location,
            LayerEnum.RAW,
            None,
            partition_cols,
        ).load_and_register(df, format_options)
    else:
        df = postgres_consumer.get_data_from_table(args.table_name)
        FullTableLoaderPipeline(
            database_name, args.table_name, database_location, LayerEnum.RAW, None
        ).load_and_register(df, format_options)


if __name__ == "__main__":
    main()
