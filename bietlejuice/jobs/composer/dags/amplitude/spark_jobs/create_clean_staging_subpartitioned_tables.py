import logging
from datetime import datetime
from argparse import ArgumentParser
import re

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
from bietlejuice.jobs.composer.base.db import (
    DatalakeMetastoreService,
    DDL_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.base.etl import FileService
from bietlejuice.jobs.composer.etl.transformer import Transformer
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_clean_staging_subpartitioned_tables")

parser = ArgumentParser(description="create_clean_staging_subpartitioned_tables")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("source")
parser.add_argument("source_table_name")
parser.add_argument("target_table_name")
parser.add_argument("--spark", action="store_true", dest="spark_flag")
parser.add_argument("--athena", action="store_true", dest="athena_flag")


def is_valid_table_name(value):
    return re.match(r"[0-9a-z_]+$", str(value))


def create_subpartitioned_table_in_spark(subpartitioned_table_name, row):
    ddl = ddl_template.format(
        clean_staging_db=db_info["db_clean_staging_databricks"],
        subpartitioned_table_name=subpartitioned_table_name,
        clean_db=db_info["db_clean_databricks"],
        source_table_name=source_table_name,
        clean_staging_source_path=db_info["db_clean_staging_path"],
        target_table_name=target_table_name,
        partition_values_path="/".join(
            ["{}={}".format(key, getattr(row, key)) for key in row.asDict()]
        ),
    )
    spark.sql(ddl)
    spark_metastore_service.repair_table_partitions(subpartitioned_table_name)
    logger.info(
        "m=__main__, msg=Table created in spark metastore and partitions repaired"
    )


def create_subpartitioned_table_in_athena(subpartitioned_table_name):
    table_location = spark_metastore_service.get_table_path(subpartitioned_table_name)
    transformer.overwrite_athena_table(
        subpartitioned_table_name,
        "clean_staging",
        partition_by=["year", "month", "day"],
        table_location=table_location,
    )
    old_athena_client.repair_table_partitions(
        db_info["db_clean_staging_athena"], subpartitioned_table_name
    )
    logger.info(
        "m=__main__, msg=Table created in athena metastore and partitions repaired"
    )


def create_subpartitioned_tables(row, subpartitioned_table_name):
    if not is_valid_table_name(subpartitioned_table_name):
        logger.warning(
            "m=__main__, subpartitioned_table_name={}, msg=Not a valid table name, "
            "table will not be created.".format(subpartitioned_table_name)
        )
        return

    logger.info(
        "m=__main__, subpartitioned_table_name={}, msg=Creating table...".format(
            subpartitioned_table_name
        )
    )
    if spark_flag and subpartitioned_table_name not in spark_existing_tables:
        create_subpartitioned_table_in_spark(subpartitioned_table_name, row)

    if athena_flag and subpartitioned_table_name not in athena_existing_tables:
        create_subpartitioned_table_in_athena(subpartitioned_table_name)


if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    source = args.source
    source_table_name = args.source_table_name
    target_table_name = args.target_table_name
    spark_flag = args.spark_flag
    athena_flag = args.athena_flag

    logger.info(
        "m=__main__, date={}, source={}, source_table_name={}, "
        "target_table_name={}, spark_flag={}, athena_flag={} msg=Job started".format(
            execution_date,
            source,
            source_table_name,
            target_table_name,
            spark_flag,
            athena_flag,
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
    ddl_template = FileService.get_query_from_file_name(
        DDL_DATALAKE_PATH
        + "clean_staging/clean_staging_subpartitioned_table_template.ddl"
    )

    # TODO: remove old athena client and transformer from the code when
    #  AthenaMetastoreService and new transformer are available
    old_athena_client = OldAthenaClient()
    transformer = Transformer(env, source, old_athena_client)
    athena_client = AthenaClient()

    # get subpartitions values
    subpartitions_values = sqlContext.table(
        "{}.subpartitions_values".format(db_info["db_clean_staging_databricks"])
    ).collect()

    # get existing tables
    if spark_flag:
        spark_existing_tables = spark_metastore_service.get_table_names()

    if athena_flag:
        old_athena_client.create_database(
            db_info["db_clean_staging_athena"]
        )  # if not exists
        athena_existing_tables = [
            row["Data"][0]["VarCharValue"]
            for row in athena_client.get_records(
                "show tables in {}".format(db_info["db_clean_staging_athena"])
            )["ResultSet"]["Rows"]
        ]

    # create clean staging subpartitioned tables
    for row in subpartitions_values:
        subpartitioned_table_name = "_".join(str(col) for col in row) + "_events"
        create_subpartitioned_tables(row, subpartitioned_table_name)
