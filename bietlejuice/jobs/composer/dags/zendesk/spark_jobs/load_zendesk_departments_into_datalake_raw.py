import json
import logging
from datetime import datetime
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from quintoandar_zendesk_client import ZendeskClient

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.api_consumers.zendesk import (
    ZendeskFactoryConsumer,
)
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.dags.zendesk import CHATS as CHATS_PREFIX

DATABRICKS_SCOPE = "quintoandar"

JOB_NAME = "load_zendesk_departments_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description="load_zendesk_departments_into_datalake")
    parser.add_argument(
        "endpoint_name", type=str, help="which endpoint to call and table name"
    )
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")
    args = parser.parse_args()

    logger.info(
        "m=load_zendesk_departments_into_datalake_raw, endpoint_name={}, execution_date={}, "
        "environment={}, msg=print args spark jobs params".format(
            args.endpoint_name, args.execution_date, args.environment
        )
    )

    execution_date = args.execution_date
    endpoint_name = args.endpoint_name
    environment = args.environment
    datalake_bucket = args.datalake_bucket
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

    zendesk_consumer = ZendeskFactoryConsumer.factory(
        zendesk_client=zendesk_client,
        spark_client=spark_sql_client,
        endpoint=endpoint_name,
        execution_date=dt_exec,
    )
    df = zendesk_consumer.request_api_and_get_dataframe(endpoint_name)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    table_name = f"{CHATS_PREFIX}_{endpoint_name}"
    s3_loader.load_full_table(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
    )
    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )
