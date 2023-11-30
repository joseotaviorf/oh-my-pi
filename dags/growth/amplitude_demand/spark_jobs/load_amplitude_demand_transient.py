import json
import gc
from argparse import ArgumentParser
from datetime import datetime, timedelta
from zipfile import ZipFile
from time import sleep

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.api_clients.amplitude_client import AmplitudeClient
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.file_service import FileService
from bietlejuice.services.configuration_service import ConfigurationService

from pyspark.sql.functions import col, year, month, dayofmonth, hour
from pyspark.sql import DataFrame

JOB_NAME = "load_amplitude_demand_transient"
AMPLITUDE_API_DATE_FORMAT = "%Y%m%dT%H"

# Timeout between retries in seconds.
BACKOFF_FACTOR = 5
# Maximum number of retries for errors.
MAX_RETRIES = 5

logger = QuintoAndarLogger(JOB_NAME)

def release_memory(dataframe: DataFrame) -> None:
    """
    The function releases memory by unpersisting the dataframe, deleting the dataframe object, and
    running garbage collection.
    
    :param dataframe: The `dataframe` parameter is a DataFrame object that you want to release from
    memory
    :type dataframe: DataFrame
    """
    dataframe.unpersist(blocking=True)
    del dataframe
    gc.collect()


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = args.execution_date

    start_date = datetime.strptime(execution_date, "%Y-%m-%d")
    end_date = start_date + timedelta(hours=23)

    date_times = []
    date_time = start_date
    while date_time <= end_date:
        date_times.append(date_time.strftime(AMPLITUDE_API_DATE_FORMAT))
        date_time += timedelta(hours=1)
    all_time_ranges_list = list(zip(*(iter(date_times),) * 2))

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    all_keys = json.loads(dbutils.secrets.get("quintoandar", APIEnum.AMPLITUDE))

    keys = [key for key in all_keys if key['app_id'] == 170698]
    
    config_service = ConfigurationService(source)
    custom_records_per_file = config_service.get_config("custom_records_per_file")
    partition_cols = config_service.get_config("transient_partition_cols")
    table_name = config_service.get_config("table_name")
    database_location = config_service.get_config("transient_location")

    spark_client = SparkClient()
    spark_context = spark_client.conn.sparkContext
    dataframe_service = SparkDataFrameService()
    s3_loader = S3Loader()


    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    stages = [all_time_ranges_list[i * 4:(i + 1) * 4] for i in range((len(all_time_ranges_list) + 3) // 4 )]  

    for key in keys:
        logger.info(
            "msg=starting events requests, app_id={}, app_name={}".format(
                key["app_id"], key["app_name"]
            )
        )
        
        for time_ranges_list in stages:

            logger.info(
                f"m=get_event_data_files, msg=starting range {min(time_ranges_list)[0]} to {max(time_ranges_list)[1]}."
            )

            retry_count = 0
            exceptions = []
            while retry_count < MAX_RETRIES:

                try:
                    amplitude_client = AmplitudeClient(key["app_key"], key["secret_key"])

                    time_ranges_rdd = spark_client.conn.sparkContext.parallelize(
                        time_ranges_list
                    )
                    file_streams_responses = time_ranges_rdd.map(
                        lambda time_range: amplitude_client.get_event_data_files(
                            *time_range
                        )
                    ).collect()

                    filtered_responses = list(filter(None, file_streams_responses))

                    events_json = []
                    if filtered_responses:

                        for file_stream in filtered_responses:
                            with ZipFile(file_stream, "r") as zip_file:
                                events_json.extend(
                                    FileService.get_data_from_zip_file(zip_file)
                                )

                        logger.info(
                        f"m=get_event_data_files, msg=received {len(events_json)} events for {min(time_ranges_list)[0]} to {max(time_ranges_list)[1]}."
                        )

                    break

                except Exception as error:
                    sleep(retry_count * BACKOFF_FACTOR)

                    logger.info(
                        "msg=fail fetch events requests, retry={}, cause={}".format(
                            retry_count, error
                        )
                    )

                    exceptions.append(error)

                retry_count += 1

            if retry_count == 5:
                logger.info("msg=fail fetch events requests, max retries exception")

                exceptions_message = "\n" + "\n".join(exceptions)
                raise Exception(
                    f"Max retries achieved. Fetch events failed {MAX_RETRIES} times. Exceptions:{exceptions_message}"
                )

            elif events_json:
                df = spark_client.conn.read.json(spark_context.parallelize(events_json))

                del events_json

                df = (
                    dataframe_service.input(df)
                    .format_column_names()
                    .convert_struct_type_to_json()
                    .output()
                )
                
                df = (df.withColumn("year", year(col('server_upload_time')))
                    .withColumn("month", month(col('server_upload_time')))
                    .withColumn("day", dayofmonth(col('server_upload_time')))
                    .withColumn("hour", hour(col('server_upload_time')))
                    )

                df = df.na.drop(subset=partition_cols)

                s3_loader.load_df(
                    df=df,
                    s3_path=f"{database_location}{table_name}",
                    format_options=format_options,
                    partitions=partition_cols,
                    max_records_per_file=custom_records_per_file,
                    optimize_dataframe=False,
                )

                release_memory(df)