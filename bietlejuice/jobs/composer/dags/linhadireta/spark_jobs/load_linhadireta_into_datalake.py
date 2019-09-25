import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.consumers import PostgreSQLConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader

JOB_NAME = "load_linhadireta_into_datalake"
WHITE_LIST = ["User", "User_chats", "Chat", "Chat_users"]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env
    source = "linhadireta"

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    connection_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.LINHADIRETA
    )
    connection = json.loads(connection_json)
    postgresql_consumer = PostgreSQLConsumer(connection)

    tables = postgresql_consumer.get_table_names_and_sizes().collect()
    loader = DatabaseIntoDataLakeRawLoader(environment, source)

    for table in tables:
        if table.table_name in WHITE_LIST:
            loader.load_full_table(
                consumer=postgresql_consumer, table_name=table.table_name
            )
