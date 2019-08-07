import logging

from pyspark.sql.functions import col
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import DatabaseIntoDataLakeRawLoader
from bietlejuice.jobs.composer.wrappers import AthenaClient

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_raw_external_tables")

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
        df.select("table_name").filter(col("table_name").rlike(r"^insider_")).collect()
    )

    logger.info("m=__main__, msg=Creating raw external tables...")
    for table in tables:
        loader.create_athena_external_table(
            consumer=databricks_consumer,
            table_name=table.table_name,
            db_source="insider",
        )

    logger.info("m=__main__, msg=All raw external tables were created successfully.")
