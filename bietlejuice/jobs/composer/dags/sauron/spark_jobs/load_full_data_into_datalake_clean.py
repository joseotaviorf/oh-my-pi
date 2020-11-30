import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_full_data_into_datalake_clean"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod environment")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("execution_date", help="DAG execution date")
    parser.add_argument("table_name", help="table name")

    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name

    logger.info(
        f"""
        m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        table_name={table_name}, msg=Starting spark job...
        """
    )

    layer = LayerEnum.CLEAN
    clean_query = FileService().get_query_from_file_name(
        f"{QUERIES_DATALAKE_PATH}{source}/{layer}/{table_name}.sql"
    )

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_clean_databricks"]
    database_location = db_info["db_clean_path"]

    conn_config = {"db": db_info["db_raw_databricks"]}

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    consumer = DatabricksConsumer(conn_config, spark_client)

    df = consumer.get_data_from_query(clean_query)

    format_options = SparkTableStorageFormat.DEFAULT_CLEAN

    s3_loader = S3Loader()
    s3_loader.load_full_table(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
    )

    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )

    spark_metastore_service.refresh_table(database_name, table_name)
