import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient

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
    loader = DatabaseIntoDataLakeRawLoader(environment, source)
    athena_db = "{}_{}".format(loader.datalake_db, environment)
    athena_client = AthenaClient()
    athena_client.run("CREATE DATABASE IF NOT EXISTS `{}`".format(athena_db))
    conn_config = {"db": loader.datalake_db}
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
    for table in tables:
        loader.create_athena_external_table(
            athena_client=athena_client,
            consumer=databricks_consumer,
            table_name=table,
            athena_db=athena_db,
        )

    logger.info("m=__main__, msg=All raw external tables were created successfully.")
