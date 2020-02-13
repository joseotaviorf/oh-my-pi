import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import MySqlConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.dags.kill_queue import SOURCE

JOB_NAME = "load_kill_queue_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

BLOCK_LIST = ["flyway_schema_history"]

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.KILL_QUEUE
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    mysql_consumer = MySqlConsumer(conn_config, spark_client)

    tables = mysql_consumer.get_table_names_and_sizes().collect()
    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE)
    metastore_service = SparkMetastoreService(spark_client)

    # create database if it doesn't exists
    metastore_service.create_database(db_info["db_raw_databricks"])

    loader = S3Loader(metastore_service)

    for table in tables:
        if table.table_name not in BLOCK_LIST:
            df = mysql_consumer.get_data_from_table(table.table_name)
            # the table names in the datalake must be lowercase
            loader.load_full_table(
                df=df,
                database_name=db_info["db_raw_databricks"],
                table_name=table.table_name.lower(),
                format=SparkTableStorageFormat.DEFAULT_RAW,
                database_location=db_info["db_raw_path"],
            )
