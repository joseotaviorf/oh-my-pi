import logging

from pyspark.sql.functions import col
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.etl import DataSourceIntoDataLakeLoader
from bietlejuice.jobs.composer.wrappers import AthenaClient

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_raw_external_tables")

if __name__ == "__main__":
    AthenaClient.execute_athena_query(
        "CREATE DATABASE IF NOT EXISTS `{}`".format(
            DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB
        ),
        "default",
    )
    connection = {"db": "datalake_raw_spark"}
    databricks_consumer = DatabricksConsumer(connection)
    df = databricks_consumer.get_table_names_and_sizes()
    tables = (
        df.select("table_name").filter(col("table_name").rlike(r"^docx_")).collect()
    )

    logger.info("m=__main__, msg=Creating raw external tables...")
    for table in tables:
        DataSourceIntoDataLakeLoader.create_athena_external_table(
            consumer=databricks_consumer, table_name=table.table_name, db_source="docx"
        )

    logger.info("m=__main__, msg=All raw external tables were created successfully.")
