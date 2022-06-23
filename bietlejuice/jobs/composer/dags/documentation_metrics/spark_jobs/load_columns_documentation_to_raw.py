import boto3
import logging
import yaml

from datetime import datetime
from argparse import ArgumentParser
from pyspark.sql import Row
from pyspark.sql.functions import explode_outer, map_keys, map_values
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

JOB_NAME = "load_columns_documentation_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_documentation_from_bucket(bucket, prefix, spark_client):
    s3_client = boto3.client("s3")
    documentation_paths = get_documentation_paths_from_bucket(bucket, prefix, s3_client)
    documentation_contents = get_content_from_paths(
        bucket, documentation_paths, s3_client
    )
    documentation_df = create_dataframe_from_contents(
        documentation_contents, spark_client
    )

    # reducing number of partitions
    documentation_df = documentation_df.coalesce(4)

    return documentation_df


def get_documentation_paths_from_bucket(bucket, prefix, s3_client):
    pages = s3_client.get_paginator("list_objects_v2").paginate(
        Bucket=bucket, Prefix=prefix
    )

    bucket_objects = []
    for page in pages:
        bucket_objects.extend(page["Contents"])

    documentation_paths = [
        obj["Key"]
        for obj in bucket_objects
        if "documentation/" in obj["Key"] and "/categories/" not in obj["Key"]
    ]

    return documentation_paths


def get_content_from_paths(bucket, documentation_paths, s3_client):
    s3_objects = []
    for file_path in documentation_paths:
        file_object = s3_client.get_object(Bucket=bucket, Key=file_path)
        s3_objects.append(file_object["Body"])

    documentation_contents = []
    for obj in s3_objects:
        documentation_contents.append(yaml.safe_load(obj))

    return documentation_contents


def create_dataframe_from_contents(documentation_contents, spark_client):
    # Creates df from documentation dict
    documentation_df = spark_client.create_dataframe(
        Row(**doc) for doc in documentation_contents
    )

    # Explodes field containing all the table's columns in distinct rows
    documentation_df = documentation_df.withColumn(
        "column", explode_outer(documentation_df["columns"])
    )

    # Separates the column's name from its documentation fields
    documentation_df = documentation_df.withColumn(
        "column_name", map_keys(documentation_df["column"])[0]
    ).withColumn("column_doc", map_values(documentation_df["column"])[0])

    documentation_df = (
        documentation_df.withColumn(
            "column_description", documentation_df.column_doc["description"]
        )
        .withColumn(
            "joins_with_column", documentation_df.column_doc["joins_with_column"]
        )
        .withColumnRenamed("description", "table_description")
        .withColumnRenamed("name", "table_name")
        .drop("columns")
        .drop("column")
        .drop("column_doc")
    )

    return documentation_df


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str)
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("source", type=str)
    parser.add_argument("table_name", type=str)
    parser.add_argument("execution_date_str", type=str)

    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date_str = args.execution_date_str
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    logger.info(
        f"""m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, source={source},
        table_name={table_name}, execution_date_str={execution_date_str}
        msg=Job execution started."""
    )

    config_service = ConfigurationService(source)
    documentation_bucket = config_service.get_config("DOCUMENTATION_BUCKET")
    documentation_prefix = config_service.get_config("DOCUMENTATION_PATH")
    partition_cols = config_service.get_config("PARTITION_COLUMNS")

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    # Creating metrics dataframe
    documentation_df = get_documentation_from_bucket(
        documentation_bucket, documentation_prefix, spark_client
    )
    documentation_df = (
        SparkDataFrameService()
        .input(documentation_df)
        .create_year_month_day_columns_from_date(execution_date)
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )

    # loaders
    s3_loader.load_df(
        df=documentation_df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader.update_metastore(
        documentation_df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=documentation_df,
        partition_cols=partition_cols,
    )
    spark_metastore_service.refresh_table(database_name, table_name)
