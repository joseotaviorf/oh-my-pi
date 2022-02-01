import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.s3_consumer import S3Consumer
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_full_composer_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("context", help="context of the DAG")
    parser.add_argument("table_name", help="table name for data catalog")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, context={args.context}
            datalake_bucket={args.datalake_bucket}, table_name={args.table_name},
            msg=print spark jobs args"
        """
    )

    environment = args.environment
    context = args.context
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    db_info = DatalakeMetastoreService.get_db_info(
        environment, context, datalake_bucket
    )
    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(db_info["db_raw_databricks"])
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]

    df = s3_consumer.get_data_from_file(
        path=f"{database_location}{table_name}/", format="json"
    )

    spark_metastore_loader.update_metastore(
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        force_recreate=False,
    )
