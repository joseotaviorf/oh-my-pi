import json
import logging

from argparse import ArgumentParser
from datetime import datetime
from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger
from quintoandar_teravoz_client import TeravozClient

from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.api_consumers.teravoz import (
    TeravozFactoryConsumer,
)
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader


DATABRICKS_SCOPE = "quintoandar"

JOB_NAME = "load_teravoz_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description="load_teravoz_into_datalake")

    # args passed by Airflow task
    parser.add_argument(
        "endpoint_name", type=str, help="which endpoint to call and table name"
    )
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")

    args = parser.parse_args()

    logger.info(
        "m=load_teravoz_into_datalake_raw, endpoint_name={}, execution_date={}, "
        "environment={}, msg=print args spark jobs params".format(
            args.endpoint_name, args.execution_date, args.environment
        )
    )

    execution_date = args.execution_date
    endpoint_name = args.endpoint_name
    environment = args.environment
    datalake_bucket = args.datalake_bucket

    # start Spark Session
    base_dbutils = BaseDBUtils()

    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    # get Teravoz credentials stored in Databricks secrets
    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key="TERAVOZ_API")

    credentials = json.loads(json_credentials)

    # request api and get dataframe
    teravoz_client = TeravozClient(
        api_user=credentials["teravoz_user"], api_pwd=credentials["teravoz_password"]
    )
    spark_client = SparkClient()

    teravoz_consumer = TeravozFactoryConsumer.factory(
        teravoz_client=teravoz_client,
        spark_client=spark_client,
        endpoint=endpoint_name,
        execution_date=execution_date,
    )
    df = teravoz_consumer.request_api_and_get_dataframe(endpoint_name)
    table_name = endpoint_name.replace("-", "_")

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, "teravoz", datalake_bucket
    )

    spark_metastore_service = SparkMetastoreService(spark_client)

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", int(dt_execution.year)),
            ("month", int(dt_execution.month)),
            ("day", int(dt_execution.day)),
        ]
    )
    partitions_cols = list(partitions.keys())
    df = SparkDataFrameService(df).create_columns_from_dict(partitions).output()

    # create database if not exists
    database_name = datalake_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    # loaders
    loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    loader.load_incremental_table(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partition_cols=partitions_cols,
    )
    spark_metastore_loader.save_as_table(
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partitions_cols,
        schema_merging=True,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partitions_cols,
    )
    spark_metastore_service.refresh_table(database_name, table_name)
