import logging
from multiprocessing.dummy import Pool

from pyspark.sql.functions import col
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader
from bietlejuice.jobs.composer.wrappers import AthenaClient

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_raw_external_tables")

NB_THREADS = 16


@logger
def create_raw_external_table(args):
    table_name, loader, databricks_consumer = args
    loader.create_athena_external_table(
        consumer=databricks_consumer, table_name=table_name, db_source="ebdb"
    )
    logger.info(
        "m=create_raw_external_table, table={}, msg=Finished creating table.".format(
            table_name
        )
    )


if __name__ == "__main__":
    loader = DatabaseIntoDataLakeRawLoader()
    datalake_db = loader.datalake_db
    AthenaClient.execute_athena_query(
        "CREATE DATABASE IF NOT EXISTS `{}`".format(datalake_db), "default"
    )
    connection = {"db": datalake_db}
    databricks_consumer = DatabricksConsumer(connection)
    df = databricks_consumer.get_table_names_and_sizes()
    tables = (
        df.select("table_name").filter(col("table_name").rlike(r"^ebdb_")).collect()
    )
    logger.info("m=__main__, msg=Creating raw external tables...")
    with Pool(NB_THREADS) as p:
        p.map(
            create_raw_external_table,
            [(table.table_name, loader, databricks_consumer) for table in tables],
        )
    logger.info("m=__main__, msg=All raw external tables were created successfully.")
