import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    BaseSparkContext,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.clients.api_clients import AmplitudeClient
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("load_events_into_datalake_raw")

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()

spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

parser = ArgumentParser(description="load_events_into_datalake_raw")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")

if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket

    start_date = datetime.strptime(execution_date, "%Y-%m-%d")
    end_date = start_date + timedelta(hours=23)
    start = start_date.strftime(AmplitudeEvents.AMPLITUDE_API_DATE_FORMAT)
    end = end_date.strftime(AmplitudeEvents.AMPLITUDE_API_DATE_FORMAT)

    keys = json.loads(dbutils.secrets.get("quintoandar", "ENV_AMPLITUDE"))

    source = "amplitude"
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    spark_client = SparkClient()
    amplitude_events = AmplitudeEvents(spark_client)
    dataframe_service = SparkDataFrameService()
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    database_name = db_info["db_raw_databricks"]
    table_name = "events"
    partition_cols = ["year", "month", "day", "app"]

    logger.info(
        "m=load_events_into_datalake_raw, Param Start String: start={} end={}".format(
            start, end
        )
    )
    for key in keys:
        app_key = key["app_key"]
        logger.info(
            "m=load_events_into_datalake_raw, App id: {}, App name: {}".format(
                key["app_id"], key["app_name"]
            )
        )
        amplitude_export_api = AmplitudeClient(key["app_key"], key["secret_key"])
        logger.info("m=load_events_into_datalake_raw, get_files_from_extract_api")
        file_from_api = amplitude_export_api.get_event_data_files(start, end)
        if file_from_api:
            df = amplitude_events.create_raw_events_df(file_from_api, dataframe_service)
            df = df.na.drop(subset=partition_cols)
            format_options = SparkTableStorageFormat.DEFAULT_RAW
            database_location = db_info["db_raw_path"]
            s3_loader.load_incremental_table(
                df=df,
                database_name=database_name,
                table_name=table_name,
                format_options=format_options,
                database_location=database_location,
                partition_cols=partition_cols,
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
            metastore_service.create_new_partitions_from_df(
                database_name, table_name, df, partition_cols, parallelism=8
            )
