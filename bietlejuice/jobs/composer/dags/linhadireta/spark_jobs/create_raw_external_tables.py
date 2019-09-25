import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader
from bietlejuice.jobs.composer.wrappers import AthenaClient

JOB_NAME = "create_raw_external_tables"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env
    source = "linhadireta"

    loader = DatabaseIntoDataLakeRawLoader(environment, source)
    athena_db = "{}_{}".format(loader.datalake_db, environment)
    athena_client = AthenaClient()
    athena_client.execute_athena_query(
        "CREATE DATABASE IF NOT EXISTS `{}`".format(athena_db), "default"
    )
    connection = {"db": loader.datalake_db}
    databricks_consumer = DatabricksConsumer(connection)
    tables = databricks_consumer.get_table_names_and_sizes().collect()

    logger.info("m=__main__, msg=Creating raw external tables...")
    for table in tables:
        loader.create_athena_external_table(
            athena_client=athena_client,
            consumer=databricks_consumer,
            table_name=table.table_name,
            athena_db=athena_db,
        )

    logger.info("m=__main__, msg=All raw external tables were created successfully.")
