import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader

JOB_NAME = "load_docx_into_datalake"
BLACK_LIST = ["flyway_schema_history"]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env
    source = "docx"

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.DOCX)
    conn_config = json.loads(conn_config_json)
    spark_sql_client = SparkClient()
    posgresql_consumer = PostgresConsumer(conn_config, spark_sql_client)

    tables = posgresql_consumer.get_table_names_and_sizes().collect()
    loader = DatabaseIntoDataLakeRawLoader(environment, source)

    for table in tables:
        if table.table_name not in BLACK_LIST:
            loader.load_full_table(
                consumer=posgresql_consumer, table_name=table.table_name
            )
