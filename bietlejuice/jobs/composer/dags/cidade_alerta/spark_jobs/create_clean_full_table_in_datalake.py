import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.dags.cidade_alerta import (
    SOURCE,
    QUERIES_CIDADE_ALERTA_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.services import FileService

JOB_NAME = "create_clean_table_in_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    # args passed by Airflow task
    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")

    args = parser.parse_args()

    table_name = args.table_name
    environment = args.environment
    datalake_bucket = args.datalake_bucket

    query = FileService().get_query_from_file_name(
        QUERIES_CIDADE_ALERTA_DATALAKE_PATH + "/clean/" + table_name + ".sql"
    )

    # get pattern schemas
    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)

    spark_client = SparkClient()

    conn_config = {"db": db_info["db_raw_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, spark_client)
    df = databricks_consumer.get_data_from_query(query)

    spark_metastore_service = SparkMetastoreService(spark_client)
    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(db_info["db_clean_databricks"])

    loader = S3Loader(SparkMetastoreService(spark_client))
    loader.load_full_table(
        df=df,
        database_name=db_info["db_clean_databricks"],
        table_name=f"{table_name}",
        format=SparkTableStorageFormat.DEFAULT_CLEAN,
        database_location=db_info["db_clean_path"],
    )
