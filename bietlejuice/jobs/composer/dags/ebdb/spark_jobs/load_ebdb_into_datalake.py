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
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_ebdb_into_datalake"
TABLE_BLOCK_LIST = ["REVCHANGES", "_UsuarioRevisionEntity_new"]
VIEW_ALLOW_LIST = ["MapRegiao", "vw_lead_reason"]
BLOCK_LIST = ["PoligonoRegiao"]

# todo: check this value and argument the choice
PARTITION_SIZE = 512
# todo: check this value and argument the choice
NB_THREADS = 20

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

Relation = collections.namedtuple("Relation", ["name", "size"])


@logger
def validate_table(t):
    if (
        t.table_name
        and t.size
        and t.table_name not in TABLE_BLOCK_LIST
        and "tmp_" not in t.table_name
    ):
        logger.info("m=Table {} is valid and can be loaded!".format(t.table_name))
        return True
    return False


@logger
def load_relation_into_datalake(args):
    """
    Loads tables and views into datalake
    """
    s3_loader, spark_metastore_loader, consumer, rel, db_info = args
    num_partitions = int(math.ceil(float(rel.size) / PARTITION_SIZE))
    if num_partitions > 1:
        df = consumer.get_data_from_table_in_parallel(rel.name, num_partitions)
    else:
        df = consumer.get_data_from_table(rel.name)
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    s3_loader.load_full_table(
        df=df,
        database_name=database_name,
        table_name=rel.name.lower(),
        format_options=format_options,
        database_location=database_location,
    )

    spark_metastore_loader.update_metastore(
        df, database_name, rel.name.lower(), format_options, database_location
    )
    logger.info(
        "m=load_relation_into_datalake, relation={}, msg=Finished loading "
        "relation.".format(rel.name)
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = "ebdb"

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.EBDB)
    conn_config = json.loads(conn_config_json)
    mysql_consumer = MySqlConsumer(conn_config, SparkClient())

    # Fix incompatibility between mysql zero-datetime and spark
    conn_config.update({"params": {"zeroDateTimeBehavior": "convertToNull"}})

    tables = mysql_consumer.get_table_names_and_sizes().collect()
    rels = [
        Relation(name=t.table_name, size=t.size)
        for t in tables
        if validate_table(t) and t.table_name not in BLOCK_LIST
    ]

    rels.extend([Relation(name=view_name, size=1) for view_name in VIEW_ALLOW_LIST])

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(SparkClient())
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    metastore_service.create_database(db_info["db_raw_databricks"])

    with Pool(NB_THREADS) as p:
        p.map(
            load_relation_into_datalake,
            [
                (s3_loader, spark_metastore_loader, mysql_consumer, rel, db_info)
                for rel in rels
            ],
        )
