import logging
from datetime import datetime
from argparse import ArgumentParser
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import (
    spark,
    sqlContext,
    SparkMetastoreService,
)
from bietlejuice.jobs.composer.wrappers import (
    SparkSQLCLient,
    AthenaClient as OldAthenaClient,
)
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("update_clean_staging_subpartitioned_tables")

parser = ArgumentParser(description="update_clean_staging_subpartitioned_tables")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("source")
parser.add_argument("--spark", action="store_true", dest="spark_flag")
parser.add_argument("--athena", action="store_true", dest="athena_flag")

NB_THREADS = 8


def update_daily_partition(row):
    subpartitioned_table_name = "_".join(str(col) for col in row) + "_events"
    partition_by_dict = {"year": year, "month": month, "day": day}

    if spark_flag and subpartitioned_table_name in spark_existing_tables:
        spark_metastore_service.add_partition(
            subpartitioned_table_name, partition_by_dict
        )
        logger.info("m=__main__, msg=Table in Spark metastore daily partition repaired")

    if athena_flag and subpartitioned_table_name in athena_existing_tables:
        old_athena_client.add_partition(
            db_info["db_clean_staging_athena"],
            subpartitioned_table_name,
            partition_by_dict,
        )
        logger.info(
            "m=__main__, msg=Table in Athena metastore daily partition repaired"
        )


if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
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
    db_info = DatalakeMetastoreService.get_db_info(env, source)
    spark_sql_client = SparkSQLCLient(spark, sqlContext)
    spark_metastore_service = SparkMetastoreService(
        db_info["db_clean_staging_databricks"],
        db_info["db_clean_staging_path"],
        spark_sql_client,
    )
    # TODO: remove old athena client from the code when new
    #  AthenaMetastoreService available
    old_athena_client = OldAthenaClient()
    athena_client = AthenaClient()

    # get subpartitions values
    subpartitions_values = sqlContext.table(
        "{}.subpartitions_values".format(db_info["db_clean_staging_databricks"])
    ).collect()

    # get existing tables
    if spark_flag:
        spark_existing_tables = spark_metastore_service.get_table_names()

    if athena_flag:
        athena_existing_tables = [
            row["Data"][0]["VarCharValue"]
            for row in athena_client.get_records(
                "show tables in {}".format(db_info["db_clean_staging_athena"])
            )["ResultSet"]["Rows"]
        ]

    # update clean staging subpartitioned tables daily partition
    with Pool(NB_THREADS) as p:
        p.map(update_daily_partition, [(row) for row in subpartitions_values])
