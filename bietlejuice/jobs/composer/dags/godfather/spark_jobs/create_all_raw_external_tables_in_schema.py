import logging
from argparse import ArgumentParser
from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.wrappers.athena_client import AthenaClient

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
    athena_client = AthenaClient()

    conn_config = {"db": db_info["db_raw_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, SparkClient())

    # create all raw external tables in schema
    tables = [
        row.table_name
        for row in databricks_consumer.get_table_names_and_sizes().collect()
        if row.table_name.startswith(schema)
    ]
    logger.info(
        "m=__main__, schema={}, tables={}, msg=Creating raw external tables...".format(
            schema, tables
        )
    )
    for table_name in tables:
        table_schema = OrderedDict(
            [
                (row["col_name"], row["col_type"].lower())
                for row in databricks_consumer.get_table_schema(table_name).collect()
            ]
        )
        athena_client.overwrite_external_table(
            database=athena_db,
            table_name=table_name,
            s3_table_path=db_info["db_raw_path"] + table_name,
            table_schema=table_schema,
            partition_by=None,
            base_format=TableStorageFormat.DEFAULT_RAW,
        )

        logger.info(
            "m=__main__, msg=All raw external tables were created successfully."
        )
