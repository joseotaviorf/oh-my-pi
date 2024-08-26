import json
import logging
import ast
from argparse import ArgumentParser
from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.base.spark import SparkDataFrameService
from bietlejuice.base.notification.slack_webhooks_enum import SlackWebhooksEnum
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.messaging_services.slack_service import SlackService

from quintoandar_velo_neurotech_api_client.clients import VeloNeurotechClient
from quintoandar_velo_neurotech_api_client.consumers import VeloNeurotechConsumer

from pyspark.sql.types import StructField, StructType, StringType


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def convert_datetime_to_neurotech_format(datetime_object):
    return datetime_object.strftime("%d/%m/%Y %H:%M:%S")


def sync_data(username, password, client_id, client_secret, end_date, report_name):
    """
    Method for calling the VeloNeuroTech and getting data for the specific time range
    :param username: username for authentication
    :param password: password for authentication
    :param client_id: client_id for authentication
    :param client_secret: client_secret for authentication
    :param start_date: start date for querying log data
    :param end_date: end date for querying log data
    :return: Json list zof returned records
    """
    start_date = end_date - timedelta(days=1)
    start_date = datetime(
        start_date.year, start_date.month, start_date.day, hour=23, minute=59
    )
    start_date = convert_datetime_to_neurotech_format(start_date)

    end_date = datetime(end_date.year, end_date.month, end_date.day, hour=23, minute=59)
    # fix execution date given by Airflow which is delayed by 1 day
    end_date = end_date + timedelta(days=1)
    end_date = convert_datetime_to_neurotech_format(end_date)

    client = VeloNeurotechClient(username, password, client_id, client_secret)
    consumer = VeloNeurotechConsumer(client=client)

    logging.info(
        f"m=sync_data, report_name={report_name}, start_date={start_date}, end_date={end_date}"
    )

    return consumer.sync(report_name, start_date, end_date)


def __generate_schema(dataframe):
    """
    This method creates the schema from the data returned by the API.
    @param dataframe: datafame with data returned by the API.
    @return: StructType
    """
    return StructType(
        [StructField(column_name, StringType()) for column_name in dataframe.columns]
    )


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("execution_date", help="execution date in str format %Y-%m-%d")
    parser.add_argument("table_name", help="Name of the table to store data into")
    parser.add_argument("partitions", help="Partition columns name")
    parser.add_argument("report_name", help="Name of the report to load data from Neurotech")
    args = parser.parse_args()

    args.partition_cols = ast.literal_eval(args.partitions)
    report_name = args.report_name

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, datalake_bucket={args.datalake_bucket}, source={args.source}, execution_date={args.execution_date},
            table_name={args.table_name} msg=Starting spark job..."
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.VELO_NEUROTECH
    )
    credentials = json.loads(json_credentials)

    dt_execution = datetime.strptime(args.execution_date, "%Y-%m-%d").date()

    pandas_df = sync_data(
        username=credentials["username"],
        password=credentials["password"],
        client_id=credentials["client_id"],
        client_secret=credentials["client_secret"],
        end_date=dt_execution,
        report_name=report_name,
    )

    if len(pandas_df) == 0:
        logger.warn(f"m={JOB_NAME}, msg=result is empty")

        slack_webhook = dbutils.secrets.get(
            scope="quintoandar", key=SlackWebhooksEnum.ALERTS_AIRFLOW_DE_DAGS_INMETRO
        )

        message = (
            f":warning:\n"
            f"DAG: *{args.source}*\n"
            f"Report: *{report_name}*\n"
            f"Environment: *{args.environment}*\n"
            f"Status: *FAILED*\n"
            f"*Existence validation failed for `{datetime.now().strftime('%Y-%m-%d')}`\n"
        )

        logger.info(f"m=__main__, message=sending slack message: {message}")
        SlackService.send_slack_errors([(message,slack_webhook)])

    else:
        spark_client = SparkClient()
        df = spark_client.create_dataframe(pandas_df, __generate_schema(pandas_df))
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(dt_execution)
            .optimize_partition(200000)
            .output()
        )

        datalake_info = DatalakeMetastoreService.get_db_info(
            args.environment, args.source, args.datalake_bucket
        )
        spark_metastore_service = SparkMetastoreService(spark_client)
        database_name = datalake_info["db_raw_databricks"]
        spark_metastore_service.create_database(database_name)

        database_location = datalake_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        table_name = args.table_name

        s3_loader = S3Loader()
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name.lower()}",
            format_options=format_options,
            partitions=args.partition_cols,
        )

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            args.partition_cols,
            force_recreate=True,
        )
        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=args.partition_cols,
        )
