import logging
from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

import bietlejuice.jobs.composer.db as db_module
from bietlejuice.jobs.composer.wrappers import AthenaClient
from bietlejuice.jobs.composer.base.spark.base_spark import BaseDBUtils
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("add_clean_events_partitions")

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()

parser = ArgumentParser(description="add_clean_events_partitions")
parser.add_argument("execution_date")
parser.add_argument("env")

NB_THREADS = 8


def create_partition(args):
    year, month, day, event_type, db_clean_athena, table_name, athena_client = args
    partition_by_dict = OrderedDict(
        [("year", year), ("month", month), ("day", day), ("event_type", event_type)]
    )
    athena_client.add_partition(db_clean_athena, table_name, partition_by_dict)


if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    source = "amplitude"
    db_info = DatalakeMetastoreService.get_db_info(env, source)
    db_clean_athena = db_info["db_clean_athena"]
    db_clean_path = db_info["db_clean_path"]
    table_name = "events"

    athena_client = AthenaClient()
    athena_client.execute_athena_query(
        "CREATE DATABASE IF NOT EXISTS `{}`".format(db_clean_athena), "default"
    )

    # creating table if not exists
    db_module_path = [path for path in db_module.__path__][0]
    clean_amplitude_events_athena_ddl = (
        db_module_path + "/datalake/queries/amplitude/clean_events_athena.ddl"
    )
    with open(clean_amplitude_events_athena_ddl) as f:
        ddl = f.read()

    athena_client.execute_athena_query(
        ddl.format(
            db=db_clean_athena, table_name=table_name, path=db_clean_path + table_name
        ),
        "default",
    )

    partition_path = db_clean_path + "{}/year={}/month={}/day={}/".format(
        table_name, year, month, day
    )
    event_types = base_dbutils.discover_partition_values_in_path(
        partition_path, dbutils
    )

    with Pool(NB_THREADS) as p:
        p.map(
            create_partition,
            [
                (
                    year,
                    month,
                    day,
                    event_type,
                    db_clean_athena,
                    table_name,
                    athena_client,
                )
                for event_type in event_types
            ],
        )

    logger.info(
        "m=__main__, table=events, msg=New partitions were created successfully."
    )
