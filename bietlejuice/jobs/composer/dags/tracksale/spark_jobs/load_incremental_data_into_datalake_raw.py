import json
import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from quintoandar_tracksale_api_client.clients import TracksaleClient
from quintoandar_tracksale_api_client.consumers import CONSUMERS

from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient

from bietlejuice.jobs.composer.services.json_service import JsonService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_api_response(token, endpoint_name, params):

    tracksale_client = TracksaleClient(api_token=token)
    consumer_instance = CONSUMERS[endpoint_name](tracksale_client)
    api_response = consumer_instance.sync(**params)

    return api_response


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("endpoint_name", help="endpoint to call the API")
    parser.add_argument("campaign_column", help="campaign ID column name")
    parser.add_argument("campaigns_to_block", help="campaigns to be blocked")
    parser.add_argument("execution_date", help="execution date in str format")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, execution_date={args.execution_date},
            datalake_bucket={args.datalake_bucket}, endpoint_name={args.endpoint_name}, msg=print spark jobs args"
        """
    )

    environment = args.environment
    source = args.source
    execution_date = args.execution_date
    datalake_bucket = args.datalake_bucket
    endpoint_name = args.endpoint_name
    campaign_column = args.campaign_column
    campaign_column = campaign_column.split(".")
    campaigns_to_block = args.campaigns_to_block
    campaigns_to_block = list(map(int, campaigns_to_block.split(",")))
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
    api_response = get_api_response(credentials["token"], endpoint_name, api_params)

    if api_response:

        try:
            df = spark_client.create_dataframe(api_response)
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
            environment, source, datalake_bucket
        )
        spark_metastore_service = SparkMetastoreService(spark_client)
        database_name = datalake_info["db_raw_databricks"]
        spark_metastore_service.create_database(database_name)

        database_location = datalake_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        table_name = endpoint_name  # the table will have the same name as the endpoint

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
