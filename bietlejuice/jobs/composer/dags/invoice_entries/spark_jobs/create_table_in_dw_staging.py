import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.dags.invoice_entries import (
    QUERIES_INVOICE_ENTRIES_DATALAKE_PATH,
    DW_SCHEMA,
)
from bietlejuice.jobs.composer.services import FileService

JOB_NAME = "create_table_in_dw_staging"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument("environment", type=str, help="forno/prod values")

    args = parser.parse_args()

    table_name = args.table_name
    environment = args.environment

    dw_info = DatalakeMetastoreService.get_dw_info(environment, DW_SCHEMA)

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)

    query = FileService.get_query_from_file_name(
        QUERIES_INVOICE_ENTRIES_DATALAKE_PATH + "/dw/" + table_name + ".sql"
    )

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(dw_info["dw_staging_databricks"])

    # conn_config wasn't used, but the class required conn_config to be instantiated
    conn_config = {"db": dw_info["dw_staging_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, spark_client)
    df = databricks_consumer.get_data_from_query(
        query
    )  # does not depend on conn_config

    loader = S3Loader(spark_metastore_service)
    loader.load_full_table(
        df=df,
        database_name=dw_info["dw_staging_databricks"],
        table_name=f"{table_name}",
        format=SparkTableStorageFormat.DEFAULT_DW_STAGING,
        database_location=dw_info["dw_staging_path"],
    )
