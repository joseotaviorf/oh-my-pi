import json
import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from quintoandar_twitter_api_client.clients.twitter_campaigns_client import (
    TwitterCampaignsClient,
)

from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat, BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader

from pyspark.sql.types import StructField, StructType, StringType

JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_auth(dbutils):
    auth_string = dbutils.secrets.get(scope="quintoandar", key=APIEnum.TWITTER)
    auth = json.loads(auth_string)
    return auth


def generate_schema(data):
    if len(data):
        columns = data[0].keys()
        type_array = [StructField(column_name, StringType()) for column_name in columns]
        schema = StructType(type_array)
        return schema


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("target", help="name of the target")
    parser.add_argument("media", help="name of the media")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
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
    execution_date = args.execution_date
    partition_cols = ["year", "month", "day"]

    spark_client = SparkClient()
    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, target, datalake_bucket
    )

    auth = get_auth(dbutils)
    client = TwitterCampaignsClient(execution_date, auth)
    data = client.get_data()

    database_name = datalake_info["db_raw_databricks"]
    database_location = datalake_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    spark_metastore_service.create_database(database_name)

    tables = ["campaigns", "ad_groups", "promoted_tweets", "promoted_tweets_stats"]

    for table, table_data in zip(tables, data):

        table_name = f"{media}_{table}"

        aggregated_table_data = []
        for page in table_data:
            aggregated_table_data += page

        if not len(table_data):
            continue

        schema = generate_schema(aggregated_table_data)

        df = spark_client.create_dataframe(aggregated_table_data, schema)
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(dt_execution)
            .output()
        )

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
