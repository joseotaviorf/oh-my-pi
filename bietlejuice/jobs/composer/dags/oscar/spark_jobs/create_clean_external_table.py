import logging

from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient, SparkClient
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)
from bietlejuice.jobs.composer.dags.oscar import SOURCE

JOB_NAME = "create_clean_external_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument(
        "table_name", type=str, help="table name that will be created in Athena"
    )
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("athena_query_result_location")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    table_name = args.table_name

    logger.info(
        f"m={JOB_NAME}, table_name={table_name}, env={environment}, "
        "msg=print args spark jobs params"
    )

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    athena_metastore_service = AthenaMetastoreService(
        AthenaClient(athena_query_result_location)
    )

    logger.info("m=__main__, msg=Creating Athena database if not exists...")
    athena_metastore_service.create_database(db_info["db_clean_athena"])
    spark_metastore_service = SparkMetastoreService(SparkClient())

    logger.info(f"m=__main__, msg=Creating clean {table_name} table...")
    table_schema = spark_metastore_service.get_table_schema(
        database_name=db_info["db_clean_databricks"], table_name=table_name
    )

    athena_metastore_service.drop_table(db_info["db_clean_athena"], table_name)
    athena_metastore_service.create_external_table(
        database_name=db_info["db_clean_athena"],
        table_name=table_name,
        table_location=db_info["db_clean_path"] + table_name,
        table_schema=table_schema,
        partition_cols=[],
        format_options=TableStorageFormat.DEFAULT_CLEAN,
    )

    logger.info(
        f"m=__main__, msg={table_name} clean external table were created successfully."
    )
