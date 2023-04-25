import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_sales_flow_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("table_config")
    parser.add_argument("partition_cols")
    parser.add_argument("execution_date")

    return parser.parse_args()


def get_conn_config():
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.SALES_FLOW
    )

    return json.loads(conn_config_json)


def main():
    args = parse_arguments()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    table_config = json.loads(args.table_config)
    partition_cols = json.loads(args.partition_cols)
    execution_date = args.execution_date

    logger.info(
        f"""
        m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        execution_date={execution_date}, msg=Starting spark job...
        """
    )

    conn_config = get_conn_config()

    spark_client = SparkClient()

    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    format_options = SparkTableStorageFormat.DEFAULT_RAW

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    unixtime_measure = table_config.get("unixtime_measure")
    is_incremental = table_config.get("extraction_type") == "incremental"
    date_filter_column = table_config.get("date_filter_column", "updated_at")

    if is_incremental:
        df = postgres_consumer.get_incremental_data_from_table(
            table_name=table_name,
            date_filter_column=date_filter_column,
            date_filter_value=execution_date,
            is_unixtime_col=unixtime_measure is not None,
        )
        IncrementalTableLoaderPipeline(
            database_name,
            table_name,
            database_location,
            LayerEnum.RAW,
            None,
            partition_cols,
        ).load_and_register(df, format_options)
    else:
        df = postgres_consumer.get_data_from_table(table_name)
        FullTableLoaderPipeline(
            database_name, table_name, database_location, LayerEnum.RAW, None
        ).load_and_register(df, format_options)


if __name__ == "__main__":
    main()
