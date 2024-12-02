import json
import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from quintoandar_tracksale_api_client.clients import TracksaleClient
from quintoandar_tracksale_api_client.consumers import CONSUMERS

from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from pyspark.sql.types import (
    ArrayType,
    LongType,
    StructField,
    MapType,
    StringType,
    StructType,
)

from bietlejuice.services.json_service import JsonService
from bietlejuice.base.spark import SparkDataFrameService
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.services.metastore_services import SparkMetastoreService

from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_api_response(token, table_name, params):

    tracksale_client = TracksaleClient(api_token=token)
    consumer_instance = CONSUMERS[table_name](tracksale_client)
    api_response = consumer_instance.sync(**params)

    return api_response

def get_parameters(table_name):
    campaign_string = "[{'answer': 'campaign_code','campaign': 'code','dispatch': 'campaign.code'}]"
    campaign_column = eval(campaign_string)[0][table_name]
    campaigns_to_block = "['248', '326', '327', '356']"
    return campaign_column, campaigns_to_block 

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("bucket", help="bucket value in forno/prod")
    parser.add_argument("dag_name", help="name of the API")
    parser.add_argument("table_name", help="endpoint to call the API")
    parser.add_argument("execution_date", help="execution date in str format")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, dag_name={args.dag_name}, execution_date={args.execution_date},
            bucket={args.bucket}, table_name={args.table_name}, msg=print spark jobs args"
        """
    )

    environment = args.environment
    dag_name = args.dag_name
    execution_date = args.execution_date
    bucket = args.bucket
    table_name = args.table_name
    
    campaign_column, campaigns_to_block = get_parameters(table_name)
    campaign_column = campaign_column.split(".")
    campaigns_to_block = list(map(int, eval(campaigns_to_block)))
    partition_cols = ["year", "month", "day"]

    api_params = {"start_time": execution_date, "end_time": execution_date}

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.TRACKSALE
    )
    credentials = json.loads(json_credentials)
    spark_client = SparkClient()
    api_response = get_api_response(credentials["token"], table_name, api_params)

    if table_name == "dispatch":  # TODO: Create a more beautiful way to pass schema
        schema = StructType(
            [
                StructField("campaign", MapType(StringType(), StringType(), True)),
                StructField("create_time", LongType(), True),
                StructField(
                    "customers", ArrayType(MapType(StringType(), StringType(), True))
                ),
                StructField("dispatch_code", StringType(), True),
                StructField("status", StringType(), True),
            ]
        )
    else:
        schema = None

    if api_response:

        try:
            df = spark_client.create_dataframe(api_response, schema=schema)
        except ValueError:
            df = spark_client.create_dataframe(
                JsonService.transform_json_list_terms(api_response)
            )

        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        df = df.coalesce(1)

        if len(campaign_column) > 1:
            df = df[
                ~df[campaign_column[0]]
                .getItem(campaign_column[1])
                .isin(campaigns_to_block)
            ]
        else:
            df = df[~df[campaign_column[0]].isin(campaigns_to_block)]

        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(dt_execution)
            .output()
        )

        datalake_info = DatalakeMetastoreService.get_db_info(
            environment, dag_name, bucket
        )
        spark_metastore_service = SparkMetastoreService(spark_client)
        database_name = datalake_info["db_raw_databricks"]
        spark_metastore_service.create_database(database_name)

        database_location = datalake_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        # loaders
        s3_loader = S3Loader()
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
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
        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=partition_cols,
        )
        spark_metastore_service.refresh_table(database_name, table_name)
