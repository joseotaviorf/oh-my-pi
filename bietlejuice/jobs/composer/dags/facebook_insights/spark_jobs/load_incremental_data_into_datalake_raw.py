import json
import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from quintoandar_facebook_api_client.clients import FacebookClient

from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat, BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader

JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def build_facebook_client(auth):
    fb_client = FacebookClient(auth["access_token"])
    return fb_client


def get_data(configs):
    auth = configs.pop("auth")
    fb_client = build_facebook_client(auth)
    client_response = fb_client.get_data(**configs)
    return client_response


def get_auth(dbutils):
    configs = json.loads(dbutils.secrets.get(scope="quintoandar", key=APIEnum.FACEBOOK))
    return configs


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("target", help="name of the target")
    parser.add_argument("media", help="name of the media")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("accounts", help="accounts to fetch")
    parser.add_argument("execution_date", help="execution date in str format")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.target}, media={args.media},
            execution_date={args.execution_date}, datalake_bucket={args.datalake_bucket}, msg=print spark jobs args"
        """
    )

    environment = args.environment
    target = args.target
    media = args.media
    datalake_bucket = args.datalake_bucket
    accounts = json.loads(args.accounts)
    execution_date = args.execution_date
    partition_cols = ["year", "month", "day"]

    spark_client = SparkClient()

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    configs = get_auth(dbutils)

    configs["date"] = execution_date
    configs["accounts"] = accounts

    client_response = get_data(configs)

    df = spark_client.create_dataframe(client_response)

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_date(dt_execution)
        .output()
    )

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, target, datalake_bucket
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
