import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.consumers import MySQLConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader

JOB_NAME = "load_vans_into_datalake"
BLACK_LIST = ["schema_migrations"]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env
    source = "vans"

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    connection_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.VANS)
    connection = json.loads(connection_json)
    postgresql_consumer = MySQLConsumer(connection)

    tables = postgresql_consumer.get_table_names_and_sizes().collect()
    loader = DatabaseIntoDataLakeRawLoader(environment, source)

    for table in tables:
        if table.table_name not in BLACK_LIST:
            loader.load_full_table(
                consumer=postgresql_consumer, table_name=table.table_name
            )
