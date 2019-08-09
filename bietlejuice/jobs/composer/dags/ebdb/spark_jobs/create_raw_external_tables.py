import logging
from argparse import ArgumentParser
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader
from bietlejuice.jobs.composer.wrappers import AthenaClient

JOB_NAME = "create_raw_external_tables"
NB_THREADS = 16

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


@logger
def create_raw_external_table(args):
    loader, databricks_consumer, table_name, athena_db = args
    loader.create_athena_external_table(
        consumer=databricks_consumer, table_name=table_name, athena_db=athena_db
    )
    logger.info(
        "m=create_clean_external_table, table={}, msg=Finished creating table.".format(
            table_name
        )
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env
    source = "ebdb"

    loader = DatabaseIntoDataLakeRawLoader(environment, source)
    # in glue metastore we need to distinguish schemas between environments
    athena_db = "{}_{}".format(loader.datalake_db, environment)
    AthenaClient.execute_athena_query(
        "CREATE DATABASE IF NOT EXISTS `{}`".format(athena_db), "default"
    )
    connection = {"db": loader.datalake_db}
    databricks_consumer = DatabricksConsumer(connection)
    tables = databricks_consumer.get_table_names_and_sizes().collect()

    logger.info("m=__main__, msg=Creating raw external tables...")
    with Pool(NB_THREADS) as p:
        p.map(
            create_raw_external_table,
            [
                (loader, databricks_consumer, table.table_name, athena_db)
                for table in tables
            ],
        )
    logger.info("m=__main__, msg=All raw external tables were created successfully.")
