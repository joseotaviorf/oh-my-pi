from argparse import ArgumentParser

import json
from datetime import datetime, timedelta

from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from functools import reduce

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

JOB_NAME = "load_opsgenie_raw"

logger = QuintoAndarLogger(JOB_NAME)

def _get_date_range(auth_token: str, start_date: str, end_date: str) -> list:
    """
    Function to generate a list of tuples like (AUTH TOKEN, START DATE, END DATE). 
    The start_date and end_date are the global parameters and the function return
    tuples, day by day, between the range. 
    """    
    if end_date > start_date:
        date_times = []
        date_time = start_date

        while date_time <= end_date:
            date_times.append(date_time.strftime("%d-%m-%Y"))
            date_time += timedelta(days=1)

        time_ranges = list(zip(*(iter(date_times),) * 2))
        time_ranges_list = [(auth_token, *time_range) for time_range in time_ranges]  
        
        return time_ranges_list
    
    else:
      return [(auth_token, start_date.strftime("%d-%m-%Y"), end_date.strftime("%d-%m-%Y"))]
  
def _fetch_alerts(auth_token: str, start_date: str, end_date: str) -> DataFrame:
  
    OpsgenieConf = opsgenie_sdk.configuration.Configuration()
    OpsgenieConf.api_key['Authorization'] = auth_token

    OpsgenieClient = opsgenie_sdk.api_client.ApiClient(configuration=OpsgenieConf)
    OpsgenieAlertApi = opsgenie_sdk.AlertApi(api_client=OpsgenieClient)
    
    query = f"teams: 'Analytics Engineering' AND createdAt >= {start_date} AND createdAt <= {end_date}"
    alerts = OpsgenieAlertApi.list_alerts(limit=100, query=query)
    
    try:
        data = alerts.data

        if len(data) > 0:         
              return spark.createDataFrame(
                  [item.to_dict() for item in data],
                  schema="""
                      acknowledged boolean,
                      alias string,
                      count bigint,
                      created_at timestamp,
                      id string,
                      integration struct<name:string, id:string, type:string>,
                      is_seen boolean,
                      last_occurred_at timestamp,
                      message string,
                      owner string,
                      priority string,
                      report struct<ack_time:bigint, acknowledged_by:string, close_time:bigint, closed_by:string>,
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
        else:
            logging.error(f"No data found for date range: {start_date} to {end_date}.")      
      
    except Exception as exception:
        logging.error(f"Fail to extract data. Error:{exception}")
        raise exception

def _fetch_logs(auth_token: str, log_id: str) -> DataFrame:

    OpsgenieConf = opsgenie_sdk.configuration.Configuration()
    OpsgenieConf.api_key['Authorization'] = auth_token

    OpsgenieClient = opsgenie_sdk.api_client.ApiClient(configuration=OpsgenieConf)
    OpsgenieAlertApi = opsgenie_sdk.AlertApi(api_client=OpsgenieClient)
    
    logs = OpsgenieAlertApi.list_logs(identifier=log_id)

    try:
        data = logs.data

        if len(data) > 0:
            df = spark.createDataFrame(
                    [item.to_dict() for item in data],
                    schema="""
                        created_at timestamp,
                        log string,
                        offset string,
                        owner string,
                        type string
                    """
                )
            
            return df.withColumn("id",lit(log_id))

        else:
            logging.error(f"No data found for log id: {log_id}.")      
      
    except Exception as exception:
        logging.error(f"Fail to extract data. Error:{exception}")
        raise exception

def _load_dataframe_into_datalake(df: DataFrame, raw_table_name: str, raw_partition_cols: list):
    """
    Load dataframe into datalake and update metastore.
    """
    spark_client = SparkClient()
    
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
    raw_alerts_table_name = config_service.get_config("raw_alerts_table_name")
    raw_logs_table_name = config_service.get_config("raw_logs_table_name")
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

    auth_token = credentials['token']

    """
    Fetch OpsGenie alerts data.
    """    
    time_ranges = _get_date_range(auth_token, start_date, end_date)
    alerts_data = [_fetch_alerts(*auth_and_time) for auth_and_time in time_ranges]
    filtered_alerts_data = [df for df in alerts_data if df is not None]

    dataframe_service = SparkDataFrameService()

    if len(filtered_alerts_data) > 0:         
        """
        Creating alerts dataframe.
        """        
        alerts_df = reduce(
            DataFrame.unionAll, filtered_alerts_data
        )

        alerts_df = (
            SparkDataFrameService()
            .input(alerts_df)
            .format_column_names()
            .create_year_month_day_columns_from_dataframe_column("created_at")
            .output()
        )        

        alerts_df = alerts_df.na.drop(subset=raw_partition_cols)

        _load_dataframe_into_datalake(alerts_df, raw_alerts_table_name, raw_partition_cols)

        """
        Fetch OpsGenie alert logs data.
        """
        alert_ids = [row['id'] for row in alerts_df.select('id').collect()]
        logs_data = [_fetch_logs(auth_token, id) for id in alert_ids]
        filtered_logs_data = [df for df in logs_data if df is not None]

        """
        Creating logs dataframe.
        """        
        logs_df = reduce(
            DataFrame.unionAll, filtered_logs_data
        )

        logs_df = (
            SparkDataFrameService()
            .input(logs_df)
            .format_column_names()
            .create_year_month_day_columns_from_dataframe_column("created_at")
            .output()
        )        

        logs_df = logs_df.na.drop(subset=raw_partition_cols)

        _load_dataframe_into_datalake(logs_df, raw_logs_table_name, raw_partition_cols)

    else:
        logging.error(f"No data found from {start_date} to {end_date}.")