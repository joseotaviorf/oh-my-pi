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

JOB_NAME = "load_sales_flow_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
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


def get_table_config(table_name, table_configs):
    if table_name not in table_configs:
        unixtime_measure = None
        is_incremental = True
        date_filter_column = "updated_at"
    else:
        unixtime_measure = table_configs[table_name].get("unixtime_measure")
        is_incremental = (
            table_configs[table_name].get("extraction_type") == "incremental"
        )
        date_filter_column = table_configs[table_name].get(
            "date_filter_column", "updated_at"
        )

    return unixtime_measure, is_incremental, date_filter_column


def main():
    args = parse_arguments()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = args.execution_date

    config_service = ConfigurationService(source)
    block_list = config_service.get_config("block_list")
    partition_cols = config_service.get_config("partition_cols")

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

    tables = postgres_consumer.get_table_names_and_sizes().collect()
    table_configs = config_service.get_config("tables")

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    for table in tables:
        table_name = table.table_name.lower()

        if table_name in block_list:
            continue

        unixtime_measure, is_incremental, date_filter_column = get_table_config(
            table_name, table_configs
        )

        if is_incremental:
            df = postgres_consumer.get_incremental_data_by_granularity_from_table(
                table_name,
                date_filter_column,
                execution_date,
                unixtime_measure=unixtime_measure,
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
