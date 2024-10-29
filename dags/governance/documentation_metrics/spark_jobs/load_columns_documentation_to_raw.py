import boto3
import logging
import yaml

from datetime import datetime
from argparse import ArgumentParser
from pyspark.sql import Row
from botocore.exceptions import IncompleteReadError
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_columns_documentation_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_documentation_from_bucket(bucket, prefix, spark_client):
    s3_client = boto3.client("s3")
    documentation_paths = get_documentation_paths_from_bucket(bucket, prefix, s3_client)
    documentation_contents = get_content_from_paths(
        documentation_bucket, documentation_paths, s3_client
    )
    documentation_content = extract_rows_from_docs(documentation_contents)

    # Creates df from documentation dict
    documentation_df = spark_client.create_dataframe(Row(**doc) for doc in documentation_content)

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
        if "documentation/" in obj["Key"]
           and "/categories/" not in obj["Key"]
           and "documentation/atlas/" not in obj["Key"]
    ]

    return documentation_paths


def get_content_from_paths(bucket, documentation_paths, s3_client):
    documentation_contents = []
    for file_path in documentation_paths:
        try:
          documentation_contents.append(load_yaml_from_bucket(bucket, file_path, s3_client))
        except IncompleteReadError as e:
          logger.error(f"Error getting stream for {file_path}")
          logger.error(e)
          raise e

    return documentation_contents


def load_yaml_from_bucket(bucket, prefix, s3_client):
    file_object = s3_client.get_object(Bucket=bucket, Key=prefix)
    return yaml.safe_load(file_object["Body"])


def extract_rows_from_docs(docs):
    """
    flattens the content of the documentation files to a list of dicts, each representing a
    row of the columns_documentation table
    """
    rows = []
    for doc in docs:
        doc_description = doc.get('description')
        doc_owner = doc.get('owner')
        doc_database_name = doc.get('database_name')
        doc_table_name = doc.get('name') or doc.get('table_name')
        columns = doc.get('columns')
        if columns:
            if type(columns) is list:
                # legacy schema
                for column in columns:
                    column_name = list(column.keys())[0]
                    column_description = column[column_name].get('description')
                    column_joins_with = column[column_name].get('joins_with_column')
                    rows.append({
                        "database_name": doc_database_name,
                        "table_name": doc_table_name,
                        "owner": doc_owner,
                        "table_description": doc_description,
                        "column_name": column_name,
                        "column_description": column_description,
                        "joins_with_column": column_joins_with
                    })
            elif type(columns) is dict:
                # new schema
                for column_name, column_values in columns.items():
                    column_description = column_values.get('description')
                    column_joins_with = column_values.get('joins_with_column')
                    rows.append({
                        "database_name": doc_database_name,
                        "table_name": doc_table_name,
                        "owner": doc_owner,
                        "table_description": doc_description,
                        "column_name": column_name,
                        "column_description": column_description,
                        "joins_with_column": column_joins_with
                    })
        else:
            continue

    return rows


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

    documentation_df = get_documentation_from_bucket(documentation_bucket, documentation_prefix, spark_client)

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
