import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.dags.kill_queue import (
    SOURCE,
    QUERIES_KILL_QUEUE_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.services import FileService

JOB_NAME = "create_clean_table_in_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    # args passed by Airflow task
    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")

    args = parser.parse_args()

    table_name = args.table_name
    environment = args.environment
    datalake_bucket = args.datalake_bucket

    # get query to create table
    query = FileService.get_query_from_file_name(
        QUERIES_KILL_QUEUE_DATALAKE_PATH + "/clean/" + table_name + ".sql"
    )

    # get pattern schemas
    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)

    spark_client = SparkClient()

    # get table data from Databricks Metastore and load into spark df
    conn_config = {"db": db_info["db_raw_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, spark_client)
    df = databricks_consumer.get_data_from_query(query)

    # create database to Cidade Alerta clean tables in Spark Metastore
    spark_metastore_service = SparkMetastoreService(spark_client)

    # create database if not exists
    database_name = db_info["db_clean_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN
    database_location = db_info["db_clean_path"]
    spark_metastore_service.create_database(database_name)

    # load full data file in s3 and map into Spark Metastore
    loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    loader.load_full_table(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
    )
    spark_metastore_loader.save_as_table(
        df, database_name, table_name, format_options, database_location
    )
