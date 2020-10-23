import logging

from argparse import ArgumentParser
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

    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("source", type=str, help="name of the source")
    parser.add_argument("datalake_bucket")
    parser.add_argument("athena_query_result_location")
    parser.add_argument("execution_date", type=str, help="DAG execution date")
    parser.add_argument("table_name", type=str, help="table name")
    parser.add_argument("extraction_type", type=str, help="extraction type")

    args = parser.parse_args()

    environment = args.env
    source = args.source
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    execution_date = args.execution_date
    table_name = args.table_name.lower()
    extraction_type = args.extraction_type

    logger.info(
        f"m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"athena_query_result_location={athena_query_result_location}, execution_date={execution_date}, "
        f"table_name={table_name}, extraction_type={extraction_type}, msg=Starting spark job..."
    )

    athena_metastore_service = AthenaMetastoreService(
        AthenaClient(athena_query_result_location)
    )

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_clean_athena"]
    database_location = db_info["db_clean_path"]

    logger.info("m=__main__, msg=Creating Athena database if not exists...")
    athena_metastore_service.create_database(database_name)

    spark_metastore_service = SparkMetastoreService(SparkClient())
    logger.info(f"m=__main__, msg=Creating clean {table_name} external table...")

    table_schema = spark_metastore_service.get_table_schema(
        database_name=db_info["db_clean_databricks"], table_name=table_name
    )

    if extraction_type == "full":
        athena_metastore_service.drop_table(database_name, table_name)

        athena_metastore_service.create_external_table(
            database_name=database_name,
            table_name=table_name,
            table_location=database_location + table_name,
            table_schema=table_schema,
            partition_cols=[],
            format_options=TableStorageFormat.DEFAULT_CLEAN,
        )

    else:
        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        partitions = {
            "year": dt_execution.year,
            "month": dt_execution.month,
            "day": dt_execution.day,
        }
        partition_cols = list(partitions.keys())

        athena_metastore_service.create_external_table(
            database_name=database_name,
            table_name=table_name,
            table_location=database_location + table_name,
            table_schema=table_schema,
            partition_cols=partition_cols,
            format_options=TableStorageFormat.DEFAULT_CLEAN,
        )

        athena_metastore_service.add_partitions(
            database_name, table_name, partitions=[partitions]
        )

    logger.info(
        f"m=__main__, msg={table_name} clean external table were created successfully."
    )
