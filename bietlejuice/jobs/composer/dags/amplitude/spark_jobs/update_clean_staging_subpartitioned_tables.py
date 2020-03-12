import logging
from datetime import datetime
from argparse import ArgumentParser
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import sqlContext
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient, AthenaClient
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("update_clean_staging_subpartitioned_tables")

parser = ArgumentParser(description="update_clean_staging_subpartitioned_tables")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("athena_query_result_location")
parser.add_argument("source")
parser.add_argument("--spark", action="store_true", dest="spark_flag")
parser.add_argument("--athena", action="store_true", dest="athena_flag")

NB_THREADS = 8


def update_daily_partition(row):
    subpartitioned_table_name = "_".join(str(col) for col in row) + "_events"
    partitions = [{"year": year, "month": month, "day": day}]

    if spark_flag and subpartitioned_table_name in spark_existing_tables:
        spark_metastore_service.add_partitions(
            database_name=db_info["db_clean_staging_databricks"],
            table_name="{}".format(subpartitioned_table_name),
            partitions=partitions,
        )
        logger.info("m=__main__, msg=Table in Spark metastore daily partition repaired")

    if athena_flag and subpartitioned_table_name in athena_existing_tables:
        athena_metastore_service.add_partitions(
            database_name=db_info["db_clean_staging_athena"],
            table_name="{}".format(subpartitioned_table_name),
            partitions=partitions,
        )
        logger.info(
            "m=__main__, msg=Table in Athena metastore daily partition repaired"
        )


if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    source = args.source
    spark_flag = args.spark_flag
    athena_flag = args.athena_flag

    logger.info(
        "m=__main__, date={}, env={}, source={}, spark_flag={}, "
        "athena_flag={}, msg=Job started".format(
            execution_date, env, source, spark_flag, athena_flag
        )
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)

    athena_client = AthenaClient(athena_query_result_location)
    athena_metastore_service = AthenaMetastoreService(athena_client)

    # get subpartitions values
    subpartitions_values = sqlContext.table(
        "{}.subpartitions_values".format(db_info["db_clean_staging_databricks"])
    ).collect()

    # get existing tables
    if spark_flag:
        spark_existing_tables = spark_metastore_service.get_table_names(
            db_info["db_clean_staging_databricks"]
        )

    if athena_flag:
        athena_existing_tables = [
            row["Data"][0]["VarCharValue"]
            for row in athena_metastore_service.get_table_names(
                db_info["db_clean_staging_athena"]
            )["ResultSet"]["Rows"]
        ]

    # update clean staging subpartitioned tables daily partition
    with Pool(NB_THREADS) as p:
        p.map(update_daily_partition, [(row) for row in subpartitions_values])
