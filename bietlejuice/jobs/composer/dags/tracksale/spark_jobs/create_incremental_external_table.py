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

JOB_NAME = "create_incremental_external_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    # args passed by Airflow task
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("source", type=str, help="name of the source")
    parser.add_argument("datalake_bucket")
    parser.add_argument("athena_query_result_location")
    parser.add_argument("execution_date", type=str, help="DAG execution date")
    parser.add_argument("endpoint", type=str, help="type of endpoint")

    args = parser.parse_args()

    environment = args.env
    source = args.source
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    execution_date = args.execution_date
    endpoint = args.endpoint

    logger.info(
        f"m={JOB_NAME}, endpoint={endpoint}, env={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"athena_query_result_location={athena_query_result_location}, execution_date={execution_date}, msg=print args spark jobs params"
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

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)

    athena_metastore_service = AthenaMetastoreService(
        AthenaClient(athena_query_result_location)
    )

    logger.info("m=__main__, msg=Creating Athena database if not exists...")
    athena_metastore_service.create_database(db_info["db_clean_athena"])

    spark_metastore_service = SparkMetastoreService(SparkClient())

    logger.info(f"m=__main__, msg=Creating clean {endpoint} table...")
    table_schema = spark_metastore_service.get_table_schema(
        database_name=db_info["db_clean_databricks"], table_name=endpoint
    )

    athena_metastore_service.create_external_table(
        database_name=db_info["db_clean_athena"],
        table_name=endpoint,
        table_location=db_info["db_clean_path"] + endpoint,
        table_schema=table_schema,
        partition_cols=partition_cols,
        format_options=TableStorageFormat.DEFAULT_CLEAN,
    )

    athena_metastore_service.add_partitions(
        database_name=db_info["db_clean_athena"],
        table_name=endpoint,
        partitions=[partitions],
    )

    logger.info(
        f"m=__main__, msg={endpoint} clean external table were created successfully."
    )
