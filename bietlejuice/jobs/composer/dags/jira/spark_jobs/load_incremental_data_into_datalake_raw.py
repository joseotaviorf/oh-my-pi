import json
import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from quintoandar_jira_api_client.clients import JiraClient
from quintoandar_jira_api_client.consumers import CONSUMERS

from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient

from bietlejuice.jobs.composer.services.json_service import JsonService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def sync_data(username, token, server, endpoint_name, updated_date):
    """
    Method for calling the JiraClient and the specific consumer
    :param username: username for authorization
    :param token: api token for authorization
    :param server: name of the Jira account
    :param endpoint_name: name of the Jira endpoint
    :param updated_date: updated date for querying incremental data
    :return: Json list of returned records
    """

    jira_client = JiraClient(username=username, token=token, server=server)

    consumer_instance = CONSUMERS[endpoint_name](jira_client)
    return consumer_instance.sync(**{"updated_date": updated_date})


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument("endpoint_name", help="endpoint to call the API")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, execution_date={args.execution_date},
            datalake_bucket={args.datalake_bucket}, endpoint_name={args.endpoint_name}, msg=print spark jobs args"
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.JIRA)
    credentials = json.loads(json_credentials)

    dt_execution = datetime.strptime(args.execution_date, "%Y-%m-%d").date()

    api_response = sync_data(
        username=credentials["username"],
        token=credentials["token"],
        server=credentials["server"],
        endpoint_name="issues",
        updated_date=dt_execution,
    )

    if not api_response:
        logger.warn(
            f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, execution_date={args.execution_date},
            datalake_bucket={args.datalake_bucket}, endpoint_name={args.endpoint_name}, msg=result is empty"
        """
        )

    else:
        transformed_api_response = JsonService.transform_json_list_terms(api_response)
        spark_client = SparkClient()
        df = spark_client.create_dataframe(transformed_api_response)
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
        table_name = (
            args.endpoint_name
        )  # the table will have the same name as the endpoint

        # loaders
        partition_cols = ["year", "month", "day"]

        s3_loader = S3Loader()
        s3_loader.load_incremental_table(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
            partition_cols=partition_cols,
        )

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
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
