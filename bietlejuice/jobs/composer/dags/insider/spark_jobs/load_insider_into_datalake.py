import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base import DatabaseEnum, BaseDBUtils
from bietlejuice.jobs.composer.consumers import PostgreSQLConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("load_insider_into_datalake")

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()

parser = ArgumentParser(description="load_insider_into_datalake")
parser.add_argument("env")

if __name__ == "__main__":
    args = parser.parse_args()
    env = args.env
    secrets_scope = "quintoandar-{}".format(env)

    connection_json = dbutils.secrets.get(scope=secrets_scope, key=DatabaseEnum.INSIDER)
    connection = json.loads(connection_json)
    postgres_consumer = PostgreSQLConsumer(connection)

    tables = postgres_consumer.get_table_names_and_sizes().collect()
    loader = DatabaseIntoDataLakeRawLoader()
    for table in tables:
        loader.load_full_table(consumer=postgres_consumer, table_name=table.table_name)
