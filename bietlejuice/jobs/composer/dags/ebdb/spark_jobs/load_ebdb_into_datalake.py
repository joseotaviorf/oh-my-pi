import json
import logging
import math
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base import DatabaseEnum, BaseDBUtils
from bietlejuice.jobs.composer.consumers import MySQLConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("load_ebdb_into_datalake")

DATABRICKS_SCOPE = "quintoandar-prod"
BLACK_LIST = ["REVCHANGES"]
PARTITION_SIZE = 512
NB_THREADS = 20


@logger
def load_table_into_datalake(args):
    table_name, table_size, loader, consumer = args
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
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()
    connection_json = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=DatabaseEnum.EBDB)
    connection = json.loads(connection_json)
    mysql_consumer = MySQLConsumer(connection)

    tables = mysql_consumer.get_table_names_and_sizes().collect()
    loader = DatabaseIntoDataLakeRawLoader()

    with Pool(NB_THREADS) as p:
        p.map(
            load_table_into_datalake,
            [
                (t.table_name, t.size, loader, mysql_consumer)
                for t in tables
                if t.table_name not in BLACK_LIST and t.table_name and t.size
            ],
        )
