import collections
import json
import logging
import math
from argparse import ArgumentParser
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import MySqlConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_ebdb_into_datalake"
TABLE_BLOCK_LIST = ["REVCHANGES"]
VIEW_ALLOW_LIST = ["MapRegiao"]

# todo: check this value and argument the choice
PARTITION_SIZE = 512
# todo: check this value and argument the choice
NB_THREADS = 20

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

Relation = collections.namedtuple("Relation", ["name", "size"])


@logger
def load_relation_into_datalake(args):
    """
    Loads tables and views into datalake
    """
    loader, consumer, rel, db_info = args
    num_partitions = int(math.ceil(float(rel.size) / PARTITION_SIZE))
    if num_partitions > 1:
        df = consumer.get_data_from_table_in_parallel(rel.name, num_partitions)
    else:
        df = consumer.get_data_from_table(rel.name)
    loader.load_full_table(
        df=df,
        database_name=db_info["db_raw_databricks"],
        table_name=rel.name.lower(),
        format=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=db_info["db_raw_path"],
    )
    logger.info(
        "m=load_relation_into_datalake, relation={}, msg=Finished loading "
        "relation.".format(rel.name)
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
    rels = [
        Relation(name=t.table_name, size=t.size)
        for t in tables
        if t.table_name not in TABLE_BLOCK_LIST and t.table_name and t.size
    ]

    rels.extend([Relation(name=view_name, size=1) for view_name in VIEW_ALLOW_LIST])

    db_info = DatalakeMetastoreService.get_db_info(environment, source)
    metastore_service = SparkMetastoreService(SparkClient())
    loader = S3Loader(metastore_service)

    with Pool(NB_THREADS) as p:
        p.map(
            load_relation_into_datalake,
            [(loader, mysql_consumer, rel, db_info) for rel in rels],
        )
