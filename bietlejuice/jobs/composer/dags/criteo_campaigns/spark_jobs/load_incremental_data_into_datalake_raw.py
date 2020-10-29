import json
import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from quintoandar_criteo_api_client.clients import CriteoClient

from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient

from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_api_response(accounts, execution_date):
    raw_data = list()
    for account in accounts:
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/octet-stream",
        }
        body = {
            "reportType": "CampaignPerformance",
            "startDate": f"{execution_date}T00:00:59.000Z",
            "endDate": f"{execution_date}T23:59:00.000Z",
            "dimensions": ["CampaignId", "Day"],
            "metrics": [
                "Clicks",
                "Displays",
                "Audience",
                "AdvertiserCost",
                "SalesAllPc",
                "RevenueGeneratedPc",
                "OverallCompetitionWin",
                "ECpc",
            ],
            "format": "json",
            "timezone": "GMT",
            "currency": "BRL",
        }
        data = json.dumps(body)

        client_id = account["client_id"]
        client_secret = account["client_secret"]
        criteo_client = CriteoClient(client_id=client_id, client_secret=client_secret)
        api_response = criteo_client.get_data(data, headers)
        if api_response:
            for data in api_response:
                raw_data.append(data)
    return raw_data


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("media", help="name of the media")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("accounts", help="accounts w/ id and secret for api call")
    parser.add_argument("execution_date", help="execution date in str format")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, media={args.media},
            execution_date={args.execution_date}, datalake_bucket={args.datalake_bucket}, msg=print spark jobs args"
        """
    )

    environment = args.environment
    source = args.source
    media = args.media
    datalake_bucket = args.datalake_bucket
    accounts = json.loads(args.accounts)
    execution_date = args.execution_date
    partition_cols = ["year", "month", "day"]

    spark_client = SparkClient()
    api_response = get_api_response(accounts, execution_date)

    if api_response:
        df = spark_client.create_dataframe(api_response)
        df = df.withColumnRenamed("Day", "Cost Attribution Date")
        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        df = df.coalesce(1)
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
        table_name = media

        # loaders
        s3_loader = S3Loader()
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
            is_incremental=True,
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
