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

JOB_NAME = "create_raw_external_tables"
BLOCK_LIST = ["change_owner_control", "flyway_schema_history", "inboundeventhistory"]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("athena_query_result_location")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    source = "wololo"

    # in glue metastore we need to distinguish schemas between environments
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)

    spark_metastore_service = SparkMetastoreService(SparkClient())
    tables = spark_metastore_service.get_table_names(
        database_name=db_info["db_raw_databricks"]
    )

    logger.info("m=__main__, msg=Creating raw external tables...")
    athena_db = db_info["db_raw_athena"]
    athena_metastore_service = AthenaMetastoreService(
        AthenaClient(athena_query_result_location)
    )

    for table_name in tables:
        if table_name not in BLOCK_LIST:
            table_schema = spark_metastore_service.get_table_schema(
                database_name=db_info["db_raw_databricks"], table_name=table_name
            )
            athena_metastore_service.drop_table(athena_db, table_name)
            athena_metastore_service.create_external_table(
                database_name=athena_db,
                table_name=table_name,
                table_location=db_info["db_raw_path"] + table_name,
                table_schema=table_schema,
                partition_cols=[],
                format_options=TableStorageFormat.DEFAULT_RAW,
            )

    logger.info("m=__main__, msg=All raw external tables were created successfully.")
