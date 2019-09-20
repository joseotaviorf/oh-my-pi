import json
import logging
import math
from argparse import ArgumentParser
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.consumers import MySQLConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader

JOB_NAME = "load_ebdb_into_datalake"
BLACK_LIST = ["REVCHANGES", "Negociacao"]
PARTITION_SIZE = 512
NB_THREADS = 20

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


@logger
def load_table_into_datalake(args):
    loader, consumer, table_name, table_size = args
    num_partitions = int(math.ceil(float(table_size) / PARTITION_SIZE))
    loader.load_full_table(
        consumer=consumer, table_name=table_name, concurrency=num_partitions
    )
    logger.info(
        "m=load_table_into_datalake, table={}, msg=Finished loading table.".format(
            table_name
        )
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env
    source = "ebdb"

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    connection_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.EBDB)
    connection = json.loads(connection_json)
    mysql_consumer = MySQLConsumer(connection)

    tables = mysql_consumer.get_table_names_and_sizes().collect()
    loader = DatabaseIntoDataLakeRawLoader(environment, source)

    with Pool(NB_THREADS) as p:
        p.map(
            load_table_into_datalake,
            [
                (loader, mysql_consumer, t.table_name, t.size)
                for t in tables
                if t.table_name not in BLACK_LIST and t.table_name and t.size
            ],
        )
