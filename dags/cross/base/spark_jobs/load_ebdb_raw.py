import collections
import json
import logging
import math
from argparse import ArgumentParser
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import MySqlConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService


SOURCE = "ebdb"
config_service = ConfigurationService(SOURCE)

JOB_NAME = "load_ebdb_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

Relation = collections.namedtuple("Relation", ["name", "size", "rows_count"])


@logger
def load_relation_into_datalake(args):
    """
    Loads tables and views into datalake
    """
    s3_loader, metastore_service, spark_metastore_loader, consumer, rel, db_info, partition_columns, partition_size = args
    num_partitions = int(math.ceil(float(rel.size) / partition_size))
    max_records_per_file = s3_loader.MAX_RECORDS_PER_FILE

    if num_partitions > 1:
        df = consumer.get_data_from_table_in_parallel(
            rel.name, num_partitions * 3, partition_columns
        )
        max_records_per_file = int(
            math.ceil(float(rel.rows_count) / num_partitions * 6)
        )
    else:
        df = consumer.get_data_from_table(rel.name)

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]

    s3_loader.load_df(
        df=df,
        s3_path=database_location + rel.name.lower(),
        format_options=format_options,
        max_records_per_file=max_records_per_file,
        optimize_dataframe=False,
    )

    spark_metastore_loader.update_metastore(
        df, 
        database_name, 
        rel.name.lower(), 
        format_options, 
        database_location, 
        force_recreate=True,
    )

    metastore_service.refresh_table(database_name, rel.name.lower())

    logger.info(
        "m=load_relation_into_datalake, relation={}, msg=Finished loading "
        "relation.".format(rel.name)
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("partition_size", help="partition size")
    parser.add_argument("table_name", help="name of the table being loaded")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket

    # todo: check this value and argument the choice
    size_threshold = int(args.partition_size) * 16

    partition_size = int(args.partition_size)

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.EBDB)
    conn_config = json.loads(conn_config_json)
    # Fix incompatibility between mysql zero-datetime and spark
    conn_config.update({"params": {"zeroDateTimeBehavior": "convertToNull"}})
    mysql_consumer = MySqlConsumer(conn_config, SparkClient())

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    metastore_service = SparkMetastoreService(SparkClient())
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    metastore_service.create_database(db_info["db_raw_databricks"])


    tables_df = mysql_consumer.get_single_table_names_and_sizes(args.table_name)

    tables = tables_df.collect()

    logger.info(
        "m=Tables to be loaded: %s", tables
    )

    rel = Relation(name=tables[0].table_name, size=tables[0].size, rows_count=tables[0].rows_count)

    partition_columns = mysql_consumer.get_partition_columns_from_all_tables()

    load_relation_into_datalake(
        (
            s3_loader,
            metastore_service,
            spark_metastore_loader,
            mysql_consumer,
            rel,
            db_info,
            partition_columns,
            partition_size,
        )
    )
