from argparse import ArgumentParser

import json
from datetime import datetime

import opsgenie_sdk

import logging
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_google_ads_raw"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    start_date = datetime.strptime(args.load_start_date, "%Y-%m-%d")
    end_date = datetime.strptime(args.load_end_date, "%Y-%m-%d")

    config_service = ConfigurationService(source)
    raw_table_name = config_service.get_config("raw_table_name")
    raw_partition_cols = config_service.get_config("raw_partition_cols")

    """
    Fetch login credentials.
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials = json.loads(
        dbutils.secrets.get('quintoandar', APIEnum.OPSGENIE)
    )

    """
    Fetch OpsGenie alerts data.
    """    
    OpsgenieConf = opsgenie_sdk.configuration.Configuration()
    OpsgenieConf.api_key['Authorization'] = credentials['token']

    OpsgenieClient = opsgenie_sdk.api_client.ApiClient(configuration=OpsgenieConf)
    OpsgenieAlertApi = opsgenie_sdk.AlertApi(api_client=OpsgenieClient)

    start_date_str = start_date.strftime("%d-%m-%Y")
    end_date_str = end_date.strftime("%d-%m-%Y")

    query = f"teams: 'Analytics Engineering' AND createdAt >= {start_date_str} AND createdAt <= {end_date_str}"
    alerts = OpsgenieAlertApi.list_alerts(query=query)
    
    """
    Creating dataframe.
    """
    if len(alerts.data) > 0:         
        df = spark.createDataFrame(
            [item.to_dict() for item in alerts.data],
            schema="""
                acknowledged boolean,
                alias string,
                count int,
                created_at timestamp,
                id string,
                integration struct<name:string, id:string, type:string>,
                is_seen boolean,
                last_occurred_at timestamp,
                message string,
                owner string,
                priority string,
                report struct<ack_time:int, acknowledged_by:string, close_time:int, closed_by:string>,
                responders array<struct<type:string, id:string>>,
                snoozed boolean,
                snoozed_until timestamp,
                source string,
                status string,
                tags string,
                tiny_id string,
                updated_at timestamp
            """
        )

        df = (
            SparkDataFrameService()
            .input(df)
            .format_column_names()
            .create_year_month_day_columns_from_dataframe_column("created_at")
            .output()
        )        

        df = df.na.drop(subset=raw_partition_cols)

        """
        Load data to datalake.
        """
        spark_client = SparkClient()
        spark_context = spark_client.conn.sparkContext
        dataframe_service = SparkDataFrameService()

        db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_service.create_database(database_name)

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader = S3Loader()

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{raw_table_name}",
            format_options=format_options,
            partitions=raw_partition_cols,
            optimize_dataframe=False,
            compression="gzip",
        )

        """
        Update metastore.
        """
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            raw_table_name,
            format_options,
            database_location,
            raw_partition_cols,
            force_recreate=True,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name, raw_table_name, df, raw_partition_cols
        )

    else:
        logging.error(f"No data found from {start_date} to {end_date}.")        