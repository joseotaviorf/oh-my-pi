import logging

from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient, SparkClient
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)
from bietlejuice.jobs.composer.dags.cidade_alerta import SOURCE

JOB_NAME = "create_clean_external_incremental_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    # args passed by Airflow task
    parser.add_argument(
        "table_name", type=str, help="table name that will be created in Athena"
    )
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("execution_date", type=str, help="Execution date DAG")

    args = parser.parse_args()

    environment = args.env
    table_name = args.table_name
    execution_date = args.execution_date

    logger.info(
        f"m={JOB_NAME}, table_name={table_name}, env={environment}, "
        f"execution_date={execution_date}, msg=print args spark jobs params"
    )

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", dt_execution.year),
            ("month", dt_execution.month),
            ("day", dt_execution.day),
        ]
    )
    partition_cols = list(partitions.keys())

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE)

    athena_metastore_service = AthenaMetastoreService(AthenaClient())

    logger.info("m=__main__, msg=Creating Athena database if not exists...")
    athena_metastore_service.create_database(db_info["db_clean_athena"])

    spark_metastore_service = SparkMetastoreService(SparkClient())

    logger.info(f"m=__main__, msg=Creating clean {table_name} table...")
    table_schema = spark_metastore_service.get_table_schema(
        database_name=db_info["db_clean_databricks"], table_name=table_name
    )

    athena_metastore_service.create_external_table(
        database_name=db_info["db_clean_athena"],
        table_name=table_name,
        table_location=db_info["db_clean_path"] + table_name,
        table_schema=table_schema,
        partition_cols=partition_cols,
        format_options=TableStorageFormat.DEFAULT_CLEAN,
    )

    logger.info(
        f"m=__main__, msg={table_name} clean external table were created successfully."
    )

    athena_metastore_service.add_partitions(
        database_name=db_info["db_clean_athena"],
        table_name=table_name,
        partitions=[partitions],
    )
