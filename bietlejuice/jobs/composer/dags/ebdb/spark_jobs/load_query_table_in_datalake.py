import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import MySqlConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("load_query_table_in_datalake")

JOB_NAME = "load_query_table_in_datalake"


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("table_name")
    parser.add_argument("source")

    args = parser.parse_args()
    env = args.env
    source = args.source
    table_name = args.table_name
    datalake_bucket = args.datalake_bucket

    query_path = QUERIES_DATALAKE_PATH + source + "/raw/{}.sql".format(table_name)
    query = FileService.get_query_from_file_name(query_path)

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    metastore_service = SparkMetastoreService(SparkClient())
    loader = S3Loader(metastore_service)

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.EBDB)
    conn_config = json.loads(conn_config_json)
    mysql_consumer = MySqlConsumer(conn_config, SparkClient())

    # create database if not exists
    metastore_service.create_database(db_info["db_raw_databricks"])
    df = mysql_consumer.get_data_from_query(query, table_name=table_name)

    # load
    loader.load_full_table(
        df=df,
        database_name=db_info["db_raw_databricks"],
        table_name=table_name,
        format=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=db_info["db_raw_path"],
    )
