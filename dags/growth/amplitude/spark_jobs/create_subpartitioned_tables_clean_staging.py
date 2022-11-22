from argparse import ArgumentParser
from datetime import datetime
from functools import reduce
from urllib.parse import unquote

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.athena import TableStorageFormat
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import spark, sqlContext
from bietlejuice.clients.db_clients import AthenaClient, SparkClient
from bietlejuice.formatters import StringFormatter
from bietlejuice.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)

JOB_NAME = "create_subpartitioned_tables_clean_staging"

logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(JOB_NAME)
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("athena_query_result_location")
parser.add_argument("source")
parser.add_argument("source_table_name")
parser.add_argument("--spark", action="store_true", dest="spark_flag")
parser.add_argument("--athena", action="store_true", dest="athena_flag")

ddl_template = """
    CREATE TABLE IF NOT EXISTS
        `{clean_staging_db}`.`{subpartitioned_table_name}`
    LIKE
        `{clean_db}`.`{source_table_name}`
    LOCATION
        '{clean_staging_source_path}{source_table_name}/{partition_values_path}'
"""


def create_subpartitioned_table_in_spark(subpartitioned_table_name, row):
    replace_map = ("/", "%2F"), ("[", "%5B"), ("]", "%5D")
    ddl = ddl_template.format(
        clean_staging_db=db_clean_staging_spark,
        subpartitioned_table_name=subpartitioned_table_name,
        clean_db=db_info["db_clean_databricks"],
        source_table_name=source_table_name,
        clean_staging_source_path=db_info["db_clean_staging_path"],
        partition_values_path="/".join(
            [
                "{}={}".format(
                    k, reduce(lambda a, t: str(a).replace(*t), replace_map, v)
                )
                for k, v in row.asDict().items()
            ]
        ),
    )
    spark.sql(ddl)
    spark_metastore_service.repair_table_partitions(
        db_clean_staging_spark, subpartitioned_table_name
    )
    logger.info(
        f"m=__main__, msg=Table '{subpartitioned_table_name}' created and updated"
        " in Spark metastore."
    )
    spark_metastore_service.refresh_table(
        db_clean_staging_spark, subpartitioned_table_name
    )


def create_subpartitioned_table_in_athena(subpartitioned_table_name):
    table_location = spark_metastore_service.get_table_path(
        db_clean_staging_spark, subpartitioned_table_name
    )
    table_schema = spark_metastore_service.get_table_schema(
        db_clean_staging_spark, subpartitioned_table_name
    )
    athena_metastore_service.create_external_table(
        database_name=db_clean_staging_athena,
        table_name=subpartitioned_table_name,
        table_location=table_location,
        table_schema=table_schema,
        partition_cols=["year", "month", "day"],
        format_options=TableStorageFormat.DEFAULT_CLEAN,
    )

    athena_metastore_service.repair_table_partitions(
        db_clean_staging_athena, subpartitioned_table_name
    )

    logger.info(
        "m=__main__, msg=Table created in athena metastore and partitions repaired"
    )


def create_subpartitioned_tables(row, subpartitioned_table_name):
    subpartitioned_table_name = StringFormatter.set_alphanumeric_snake_case(
        unquote(subpartitioned_table_name.replace("-", "_"))
    )

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
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    source = args.source
    source_table_name = args.source_table_name
    spark_flag = args.spark_flag
    athena_flag = args.athena_flag

    logger.info(
        f"m=__main__, date={execution_date}, source={source}, "
        f"source_table_name={source_table_name}, spark_flag={spark_flag}, "
        f"athena_flag={athena_flag}, msg=Job started"
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    db_clean_staging_athena = db_info["db_clean_staging_athena"]
    db_clean_staging_spark = db_info["db_clean_staging_databricks"]

    # get subpartitions values
    subpartitions_values = sqlContext.table(
        f"{db_clean_staging_spark}.subpartitions_values"
    ).collect()

    # get existing tables
    if spark_flag:
        spark_metastore_service = SparkMetastoreService(SparkClient())
        spark_metastore_service.create_database(db_clean_staging_spark)
        spark_existing_tables = spark_metastore_service.get_table_names(
            db_clean_staging_spark
        )

    if athena_flag:
        athena_metastore_service = AthenaMetastoreService(
            AthenaClient(athena_query_result_location)
        )
        athena_metastore_service.create_database(db_clean_staging_athena)
        athena_existing_tables = [
            row["Data"][0]["VarCharValue"]
            for row in athena_metastore_service.get_table_names(
                db_clean_staging_athena
            )["ResultSet"]["Rows"]
        ]

    # create clean staging subpartitioned tables
    for row in subpartitions_values:
        subpartitioned_table_name = "_".join(str(col) for col in row) + "_events"
        create_subpartitioned_tables(row, subpartitioned_table_name)
