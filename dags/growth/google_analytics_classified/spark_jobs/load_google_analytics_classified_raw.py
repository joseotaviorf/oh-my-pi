import base64
import json
from argparse import ArgumentParser

from google.oauth2 import service_account
from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_google_analytics_classified_raw"
logger = QuintoAndarLogger(JOB_NAME)
base_dbutils = BaseDBUtils()

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")

    add_validation_target_args(parser)
    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date

    config_service = ConfigurationService(source)

    project = config_service.get_config("project")
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    source_table_name = config_service.get_config("source_table_name")
    table_name = config_service.get_config("table_name")
    source_database_name = config_service.get_config("source_database_name")
    source_table_name = config_service.get_config("source_table_name")

    credentials_json = dbutils.secrets.get("quintoandar", APIEnum.CLASSIFIEDS_BIGQUERY)

    credentials_dict = json.loads(credentials_json)
    credentials_b64 = base64.b64encode(credentials_json.encode("utf-8")).decode("utf-8")
    credentials = service_account.Credentials.from_service_account_info(
        credentials_dict
    )

    query = f"""
    SELECT * 
    FROM `{project}.{source_database_name}.{source_table_name}` 
    WHERE 
        event_date >= DATE('{load_start_date}') 
        AND event_date <= DATE('{load_end_date}')
    """
    logger.info(f"Running query: {query}")

    spark = SparkSession.builder.getOrCreate()

    df = (
        spark.read.format("bigquery")
        .option("credentials", credentials_b64)
        .option("project", project)
        .option("parentProject", project)
        .option("query", query)
        .option("materializationDataset", source_database_name)
        .load()
    )

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("event_date")
        .output()
    )

    spark_client = SparkClient()
    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )

    spark_metastore_service.create_database(write_database_name)

    s3_loader.load_df(
        df=df,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        s3_path=f"{write_location}{write_table_name}",
        partitions=raw_partition_cols,
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=write_database_name,
        table_name=write_table_name,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=write_location,
        partitions=raw_partition_cols,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=write_database_name,
        table_name=write_table_name,
        partition_cols=raw_partition_cols,
    )
