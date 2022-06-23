import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat, BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.s3_consumer import S3Consumer
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)


JOB_NAME = "load_casa_mineira_portal_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source

    config_service = ConfigurationService(source)
    source_root_path = config_service.get_config("source_root_path")
    job_extra_args = config_service.get_config("job_extra_args")
    consumer_extra_args = job_extra_args.get("consumer")
    custom_records_per_file = job_extra_args.get("custom_records_per_file")

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                source_root_path={source_root_path}, msg=Starting spark job...
        """
    )

    # Initializing clients
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    # Retrieving folders/tables from root location.
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    tables = dbutils.fs.ls(source_root_path)

    for table in tables:
        table_name = table.name.replace("/", "")
        source_path = f"{source_root_path}{table_name}/*.csv"
        df = s3_consumer.get_data_from_file(path=source_path, **consumer_extra_args)

        db_info = DatalakeMetastoreService.get_db_info(
            environment, source, datalake_bucket
        )
        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

        logger.info(
            "m=__main__, msg=Creating database in Spark Metastore if not exists..."
        )
        database_name = db_info["db_raw_databricks"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        database_location = db_info["db_raw_path"]
        spark_metastore_service.create_database(database_name)

        s3_loader = S3Loader()

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            max_records_per_file=custom_records_per_file.get(
                table_name, s3_loader.MAX_RECORDS_PER_FILE
            ),
        )

        spark_metastore_loader.update_metastore(
            df, database_name, table_name, format_options, database_location
        )
