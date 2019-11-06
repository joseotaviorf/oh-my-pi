from datetime import datetime, timedelta
import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.wrappers import AmplitudeExportApi, SparkSQLCLient
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    BaseSparkContext,
    SparkDataFrameService,
    SparkMetastoreService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.loaders import SparkDataframeIntoDatalakeLoader

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("load_events_into_datalake_raw")

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()

spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

parser = ArgumentParser(description="load_events_into_datalake_raw")
parser.add_argument("execution_date")
parser.add_argument("env")

if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env

    start_date = datetime.strptime(execution_date, "%Y-%m-%d")
    end_date = start_date + timedelta(hours=23)
    start = start_date.strftime(AmplitudeEvents.AMPLITUDE_API_DATE_FORMAT)
    end = end_date.strftime(AmplitudeEvents.AMPLITUDE_API_DATE_FORMAT)

    keys = json.loads(dbutils.secrets.get("quintoandar", "ENV_AMPLITUDE"))

    source = "amplitude"
    db_info = DatalakeMetastoreService.get_db_info(env, source)
    amplitude_events = AmplitudeEvents()
    spark_sql_client = SparkSQLCLient(spark, sqlContext)
    dataframe_service = SparkDataFrameService()
    metastore_service = SparkMetastoreService(
        db_info["db_raw_databricks"], db_info["db_raw_path"], spark_sql_client
    )
    dataframe_loader = SparkDataframeIntoDatalakeLoader(
        SparkTableStorageFormat.DEFAULT_RAW, metastore_service
    )
    table_name = "events"
    partition_by_list = ["year", "month", "day", "app"]

    logger.info(
        "m=load_events_into_datalake_raw, Param Start String: start={} end={}".format(
            start, end
        )
    )
    for key in keys:
        logger.info(
            "m=load_events_into_datalake_raw, App id: {}, App name: {}".format(
                key["app_id"], key["app_name"]
            )
        )
        amplitude_export_api = AmplitudeExportApi(key["app_key"], key["secret_key"])
        logger.info("m=load_events_into_datalake_raw, get_files_from_extract_api")
        file_from_api = amplitude_export_api.get_files_from_extract_api(start, end)

        if file_from_api:
            df = amplitude_events.create_raw_events_df(file_from_api, dataframe_service)
            dataframe_loader.overwrite_partition(
                df, partition_by_list, table_name, schema_merging=True
            )
            metastore_service.create_new_partitions_from_df(
                table_name, df, partition_by_list, parallelism=8
            )
