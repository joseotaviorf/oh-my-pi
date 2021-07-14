import json
import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from quintoandar_criteo_api_client.clients import CriteoClient

from bietlejuice.jobs.composer.clients.db_clients import SparkClient

from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def map_cols(df):
    col_mapping = {
        "SalesAllPc1d": "All Sales",
        "Adset": "Campaign Name",
        "Advertiser": "Advertiser Name",
        "ECpc": "CPC",
        "AdsetId": "Campaign ID",
        "AdvertiserCost": "Cost",
        "OverallCompetitionWin": "Comp. Win",
        "RevenueGeneratedPc1d": "Revenue",
        "Day": "Cost Attribution Date",
        "Displays": "Impressions",
    }

    for key, value in col_mapping.items():
        df = df.withColumnRenamed(key, value)
    return df


def get_api_response(credentials, execution_date):
    headers = {"Content-Type": "application/json", "Accept": "application/octet-stream"}
    body = {
        "startDate": execution_date,
        "endDate": execution_date,
        "dimensions": ["AdsetId", "Day", "Advertiser"],
        "metrics": [
            "Clicks",
            "Displays",
            "Audience",
            "AdvertiserCost",
            "SalesAllPc1d",
            "RevenueGeneratedPc1d",
            "OverallCompetitionWin",
            "ECpc",
        ],
        "format": "json",
        "timezone": "GMT",
        "currency": "BRL",
    }

    client_id = credentials["client_id"]
    client_secret = credentials["client_secret"]
    criteo_client = CriteoClient(client_id=client_id, client_secret=client_secret)
    api_response = criteo_client.get_data(body, headers)
    return api_response


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("context", help="name of the context")
    parser.add_argument("media", help="name of the media")
    parser.add_argument("execution_date", help="execution date in str format")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, context={args.context}, media={args.media},
            execution_date={args.execution_date}, datalake_bucket={args.datalake_bucket}, msg=print spark jobs args"
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials_str = dbutils.secrets.get(scope="quintoandar", key=APIEnum.CRITEO)
    credentials = json.loads(credentials_str)
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    context = args.context
    media = args.media
    execution_date = args.execution_date
    partition_cols = ["year", "month", "day"]

    spark_client = SparkClient()
    api_response = get_api_response(credentials, execution_date)

    if api_response:
        df = spark_client.create_dataframe(api_response)
        df = map_cols(df)
        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        df = df.coalesce(1)
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(dt_execution)
            .output()
        )

        datalake_info = DatalakeMetastoreService.get_db_info(
            environment, context, datalake_bucket
        )
        spark_metastore_service = SparkMetastoreService(spark_client)
        database_name = datalake_info["db_raw_databricks"]
        spark_metastore_service.create_database(database_name)

        database_location = datalake_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        table_name = media

        # loaders
        s3_loader = S3Loader()
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
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
