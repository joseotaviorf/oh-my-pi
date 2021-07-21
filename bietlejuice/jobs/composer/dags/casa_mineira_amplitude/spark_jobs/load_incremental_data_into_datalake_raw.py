import json
import logging
from datetime import datetime, timedelta
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.api_clients import AmplitudeClient
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = args.execution_date

    start_date = datetime.strptime(execution_date, "%Y-%m-%d")
    end_date = start_date + timedelta(hours=23)
    start = start_date.strftime(AmplitudeEvents.AMPLITUDE_API_DATE_FORMAT)
    end = end_date.strftime(AmplitudeEvents.AMPLITUDE_API_DATE_FORMAT)

    logger.info(
        f"""
        msg=load_incremental_data_into_datalake_raw, environment={environment}, datalake_bucket={datalake_bucket},
        source={source}, execution_date={execution_date}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    keys = json.loads(dbutils.secrets.get("quintoandar", "ENV_CM_AMPLITUDE"))

    config_service = ConfigurationService(source, inverse_file_config_order=True)
    custom_records_per_file = config_service.get_config("custom_records_per_file")
    partition_cols = config_service.get_config("partition_cols")
    table_name = config_service.get_config("table_name")

    spark_client = SparkClient()

    amplitude_events = AmplitudeEvents(spark_client)
    dataframe_service = SparkDataFrameService()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_loader = S3Loader()

    for key in keys:
        app_key = key["app_key"]
        logger.info(
            f"""msg=load_incremental_data_into_datalake_raw, app_id={key["app_id"]}, app_name={key["app_name"]}"""
        )

        amplitude_export_api = AmplitudeClient(key["app_key"], key["secret_key"])
        logger.info("msg=Exporting files from Amplitude API...")
        file_from_api = amplitude_export_api.get_event_data_files(start, end)

        if file_from_api:
            df = amplitude_events.create_raw_events_df(file_from_api, dataframe_service)

            s3_loader.load_df(
                df=df,
                s3_path=f"{database_location}{table_name}",
                format_options=format_options,
                partitions=partition_cols,
                max_records_per_file=custom_records_per_file,
            )

            spark_metastore_loader.update_metastore(
                df,
                database_name,
                table_name,
                format_options,
                database_location,
                partition_cols,
                force_recreate=False,
            )
            spark_metastore_service.create_new_partitions_from_df(
                database_name, table_name, df, partition_cols, parallelism=8
            )
