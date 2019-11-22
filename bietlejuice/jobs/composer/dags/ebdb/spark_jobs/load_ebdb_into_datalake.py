import json
import logging
import math
from argparse import ArgumentParser
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkMetastoreService,
    SparkTableStorageFormat,
    spark,
    sqlContext,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import MySqlConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient

JOB_NAME = "load_ebdb_into_datalake"
BLACK_LIST = ["REVCHANGES"]
# todo: check this value and argument the choice
PARTITION_SIZE = 512
# todo: check this value and argument the choice
NB_THREADS = 20

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


@logger
def load_table_into_datalake(args):
    loader, consumer, table_name, table_size = args
    num_partitions = int(math.ceil(float(table_size) / PARTITION_SIZE))
    if num_partitions > 1:
        df = consumer.get_data_from_table_in_parallel(table_name, num_partitions)
    else:
        df = consumer.get_data_from_table(table_name)
    # the table names in the datalake must be lowercase
    loader.load_full_table(df, table_name.lower(), SparkTableStorageFormat.DEFAULT_RAW)
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

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.EBDB)
    conn_config = json.loads(conn_config_json)
    mysql_consumer = MySqlConsumer(conn_config, SparkClient())

    tables = mysql_consumer.get_table_names_and_sizes().collect()
    db_info = DatalakeMetastoreService.get_db_info(environment, source)
    spark_metastore_service = SparkMetastoreService(
        db_info["db_raw_databricks"],
        db_info["db_raw_path"],
        SparkSQLCLient(spark, sqlContext),
    )
    loader = S3Loader(spark_metastore_service)

    with Pool(NB_THREADS) as p:
        p.map(
            load_table_into_datalake,
            [
                (loader, mysql_consumer, t.table_name, t.size)
                for t in tables
                if t.table_name not in BLACK_LIST and t.table_name and t.size
            ],
        )
