import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.db import DWMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.dags.dw_fact_conversion_metrics import DW_SCHEMA
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat


JOB_NAME = "create_table_in_dw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dw_bucket", type=str, help="dw bucket")
    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument("environment", type=str, help="forno/prod values")

    args = parser.parse_args()
    dw_bucket = args.dw_bucket
    table_name = args.table_name
    environment = args.environment

    db_info = DWMetastoreService.get_dw_info(environment, DW_SCHEMA, dw_bucket)
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    database_name = db_info["dw_schema_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_DW
    database_location = db_info["dw_schema_path"]
    spark_metastore_service.create_database(database_name)

    conn_config = {"db": db_info["dw_staging_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, spark_client)
    df = databricks_consumer.get_data_from_table(table_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
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
