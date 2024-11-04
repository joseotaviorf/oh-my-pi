import logging

from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime
from pyspark.sql.functions import to_json, struct

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
    BaseDBUtils,
    spark,
)


JOB_NAME = "load_braze_events_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_events_from_app_group(app_group_path, dbutils):
    data_export_folders = base_dbutils.discover_directories_in_path(
        app_group_path, dbutils
    )
    events = []
    for folder in data_export_folders:
        events_in_folder = base_dbutils.discover_partition_values_in_path(
            f"{app_group_path}/{folder}", dbutils
        )
        events = list(set(events) | set(events_in_folder))
    return events


def get_event_data(app_group_path, event, execution_date):
    try:
        df = spark.read.format("avro").load(
            f"{app_group_path}/dataexport*/event_type={event}/date={execution_date}*/*/*/"
        )
    except Exception as e:
        logger.info(f"m={JOB_NAME}, error={e}")
        return None

    # serialize dataframe columns into a json string
    df = df.withColumn("event_info", to_json(struct([df[x] for x in df.columns])))
    df = df.select("id", "event_info")
    return df


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("braze_bucket")
    parser.add_argument("app_group")
    parser.add_argument("execution_date")
    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    braze_bucket = args.braze_bucket
    app_group = args.app_group
    execution_date = args.execution_date

    logger.info(
        f"""
        m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        braze_bucket={braze_bucket}, app_group={app_group}, execution_date={execution_date},
        msg=Starting spark job..."
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", dt_execution.year),
            ("month", dt_execution.month),
            ("day", dt_execution.day),
            ("event_type", ""),
        ]
    )
    partition_cols = list(partitions.keys())

    table_name = f"events_{app_group}"
    app_group_path = f"{braze_bucket}/{app_group}"
    events = get_events_from_app_group(app_group_path, dbutils)

    for event in events:
        df = get_event_data(app_group_path, event, dt_execution)
        if df:
            partitions["event_type"] = event

            df = (
                SparkDataFrameService()
                .input(df)
                .create_columns_from_dict(partitions)
                .optimize_partitions_by_partition_columns(partition_cols)
                .output()
            )

            s3_loader.load_df(
                df=df,
                s3_path=database_location + table_name,
                format_options=format_options,
                partitions=partition_cols,
                compression="gzip",
            )

            spark_metastore_loader.update_metastore(
                df=df,
                database_name=database_name,
                table_name=table_name,
                format_options=format_options,
                database_location=database_location,
                partitions=partition_cols,
                force_recreate=False,
            )

            spark_metastore_service.create_new_partitions_from_df(
                df=df,
                database_name=database_name,
                table_name=table_name,
                partition_cols=partition_cols,
            )

            spark_metastore_service.refresh_table(database_name, table_name)
