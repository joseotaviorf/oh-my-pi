import json
import logging
from datetime import datetime, timedelta
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from quintoandar_zendesk_client import ZendeskClient

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.api_consumers.zendesk import (
    ZendeskFactoryConsumer,
)
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

DATABRICKS_SCOPE = "quintoandar"

JOB_NAME = "load_zendesk_chats_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description="load_zendesk_chats_into_datalake")

    # args passed by Airflow task
    parser.add_argument(
        "endpoint_name", type=str, help="which endpoint to call and table name"
    )
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument(
        "days_interval_start", type=str, help="start interval of days to reprocess"
    )
    parser.add_argument(
        "days_interval_end", type=str, help="end interval of days to reprocess"
    )
    parser.add_argument("environment", type=str, help="forno/prod values")

    args = parser.parse_args()

    logger.info(
        "m=load_zendesk_chats_into_datalake_raw, endpoint_name={}, execution_date={}, "
        "environment={}, msg=print args spark jobs params".format(
            args.endpoint_name, args.execution_date, args.environment
        )
    )

    execution_date = args.execution_date
    endpoint_name = args.endpoint_name
    environment = args.environment
    days_interval_start = int(args.days_interval_start)
    days_interval_end = int(args.days_interval_end)
    source = "zendesk"

    # start Spark Session
    base_dbutils = BaseDBUtils()

    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    # get Zendesk credentials stored in Databricks secrets
    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key="ENV_ZENDESK")

    credentials = json.loads(json_credentials)

    # request api and get dataframe
    zendesk_client = ZendeskClient(access_token=credentials["access_token"])
    spark_sql_client = SparkClient()

    dt_exec = datetime.strptime(execution_date, "%Y-%m-%d")
    for delta_day in range(days_interval_start - 1, days_interval_end):
        dt_execution = dt_exec + timedelta(days=-delta_day)
        zendesk_consumer = ZendeskFactoryConsumer.factory(
            zendesk_client=zendesk_client,
            spark_client=spark_sql_client,
            endpoint=endpoint_name,
            execution_date=dt_execution,
        )
        df = zendesk_consumer.request_api_and_get_dataframe(endpoint_name)
        df = (
            SparkDataFrameService(df)
            .create_year_month_day_columns_from_date(dt_execution)
            .output()
        )

        db_info = DatalakeMetastoreService.get_db_info(environment, source)
        database_name = db_info["db_raw_databricks"]

        spark_client = SparkClient()
        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_service.create_database(database_name)

        loader = S3Loader(spark_metastore_service)

        partition = ["year", "month", "day"]
        loader.load_incremental_table(
            df=df,
            database_name=database_name,
            table_name=endpoint_name,
            format_options=SparkTableStorageFormat.DEFAULT_RAW,
            database_location=db_info["db_raw_path"],
            partition_cols=partition,
            schema_merging=True,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name, endpoint_name, df, partition
        )

        spark_metastore_service.refresh_table(database_name, endpoint_name)
