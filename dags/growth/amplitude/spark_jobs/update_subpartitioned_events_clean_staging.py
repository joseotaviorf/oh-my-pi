from datetime import datetime
from argparse import ArgumentParser
from multiprocessing.dummy import Pool
from urllib.parse import unquote
from functools import reduce

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.formatters.string_formatter import StringFormatter
from bietlejuice.base.spark import sqlContext
from bietlejuice.base.db.datalake_metastore_service import DatalakeMetastoreService
from bietlejuice.clients.db_clients.spark_client import SparkClient
from bietlejuice.services.metastore_services.spark_metastore_service import (
    SparkMetastoreService,
)

JOB_NAME = "update_subpartitioned_events_clean_staging"

logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(JOB_NAME)
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")

NB_THREADS = 8


def update_date_partitions(row):
    replace_map = ("/", "%2F"), ("[", "%5B"), ("]", "%5D")
    subpartitioned_table_name = "_".join(str(col) for col in row) + "_events"
    subpartitioned_table_name = reduce(
        lambda a, t: str(a).replace(*t), replace_map, subpartitioned_table_name
    )
    subpartitioned_table_name = StringFormatter.set_alphanumeric_snake_case(
        unquote(subpartitioned_table_name.replace("-", "_"))
    )
    partitions = [{"year": year, "month": month, "day": day}]

    if subpartitioned_table_name in existing_tables:
        spark_metastore_service.add_partitions(
            database_name=db_info["db_clean_staging_databricks"],
            table_name="{}".format(subpartitioned_table_name),
            partitions=partitions,
        )
        logger.info(
            "m=__main__, msg=Added partitions for execution date "
            f"'{execution_date}' on table '{subpartitioned_table_name}'."
        )
    else:
        logger.info(f"m=__main__, msg=Table {subpartitioned_table_name} do not exist.")

def get_table_names(database_name: str):
    """Returns the table names, but ignoring views"""

    return [
        t.name
        for t in spark.catalog.listTables(database_name)
        if t.tableType != "VIEW"
    ]


if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source

    logger.info(
        f"m=__main__, execution_date={execution_date}, env={env}, source={source}, "
        "msg=Job started"
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)

    # get subpartitions values
    subpartitions_values = sqlContext.table(
        "{}.subpartitions_values".format(db_info["db_clean_staging_databricks"])
    ).collect()

    # get existing tables
    existing_tables = get_table_names(
        db_info["db_clean_staging_databricks"]
    )

    # update clean staging subpartitioned tables daily partition
    with Pool(NB_THREADS) as p:
        p.map(update_date_partitions, [(row) for row in subpartitions_values])
