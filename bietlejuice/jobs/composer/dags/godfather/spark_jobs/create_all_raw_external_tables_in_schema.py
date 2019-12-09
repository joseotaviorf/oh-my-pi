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

JOB_NAME = "create_all_raw_external_tables_in_schema"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(description=JOB_NAME)
parser.add_argument("env")
parser.add_argument("source")
parser.add_argument("schema")

if __name__ == "__main__":
    args = parser.parse_args()
    environment = args.env
    source = args.source
    schema = args.schema

    # setup
    db_info = DatalakeMetastoreService.get_db_info(environment, source)
    athena_db = db_info["db_raw_athena"]
    athena_metastore_service = AthenaMetastoreService(AthenaClient())
    spark_metastore_service = SparkMetastoreService(SparkClient())

    # create all raw external tables in schema
    tables = spark_metastore_service.get_table_names(
        database_name=db_info["db_raw_databricks"], regex=f"{schema}*"
    )
    logger.info(
        "m=__main__, schema={}, tables={}, msg=Creating raw external tables...".format(
            schema, tables
        )
    )
    for table_name in tables:
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

        logger.info(
            "m=__main__, msg=All raw external tables were created successfully."
        )
