import ast
import logging
from argparse import ArgumentParser
from datetime import datetime

import boto3
import yaml
from botocore.exceptions import IncompleteReadError
from pyspark.sql import Row
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_tables_documentation_to_raw"

TABLES_DOCUMENTATION_SCHEMA = (
    "database_name string, table_name string, domain string, "
    "owner string, table_description string"
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _as_string(value):
    if value is None:
        return None
    if isinstance(value, str):
        text = value.strip()
        return text or None
    if isinstance(value, (int, float, bool)):
        return str(value)
    return None


def get_tables_documentation_from_bucket(bucket, metadata_prefix, spark_client):
    s3_client = boto3.client("s3")
    metadata_paths = get_metadata_paths_from_bucket(bucket, metadata_prefix, s3_client)
    metadata_contents = get_content_from_paths(bucket, metadata_paths, s3_client)
    table_rows = extract_table_rows_from_metadata(metadata_contents)

    documentation_df = spark_client.create_dataframe(
        [Row(**doc) for doc in table_rows],
        schema=TABLES_DOCUMENTATION_SCHEMA,
    )

    return documentation_df.coalesce(1)


def get_metadata_paths_from_bucket(bucket, prefix, s3_client):
    pages = s3_client.get_paginator("list_objects_v2").paginate(
        Bucket=bucket, Prefix=prefix
    )

    bucket_objects = []
    for page in pages:
        if "Contents" in page:
            bucket_objects.extend(page["Contents"])

    return [
        obj["Key"]
        for obj in bucket_objects
        if len(obj["Key"].split("/")) == 3 and obj["Key"].endswith((".yml", ".yaml"))
    ]


def get_content_from_paths(bucket, file_paths, s3_client):
    contents = []
    for file_path in file_paths:
        try:
            contents.append(load_yaml_from_bucket(bucket, file_path, s3_client))
        except IncompleteReadError as e:
            logger.error(f"Error getting stream for {file_path}")
            logger.error(e)
            raise e
        except Exception as e:
            logger.warning(f"Failed to load or parse {file_path}: {e}")

    return contents


def load_yaml_from_bucket(bucket, prefix, s3_client):
    file_object = s3_client.get_object(Bucket=bucket, Key=prefix)
    return yaml.safe_load(file_object["Body"])


def extract_table_rows_from_metadata(docs):
    """
    Flattens metadata/{database}/{table}.yml files into rows for tables_documentation.
    """
    rows = []
    for doc in docs:
        if not doc:
            continue

        database_name = _as_string(doc.get("database_name"))
        table_name = _as_string(doc.get("table_name"))

        if not database_name or not table_name:
            if doc.get("database_name") or doc.get("table_name"):
                logger.warning(
                    "m=extract_table_rows_from_metadata, msg=skipping row with invalid "
                    "database_name or table_name types"
                )
            continue

        rows.append(
            {
                "database_name": database_name,
                "table_name": table_name,
                "domain": _as_string(doc.get("domain")),
                "owner": _as_string(doc.get("owner")),
                "table_description": _as_string(doc.get("description")),
            }
        )

    return rows


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str)
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("source", type=str)
    parser.add_argument("table_name", type=str)
    parser.add_argument("execution_date_str", type=str)
    parser.add_argument("partitions", type=str)
    parser.add_argument("documentation_bucket", type=str)
    parser.add_argument("metadata_prefix", type=str)

    add_validation_target_args(parser)
    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date_str = args.execution_date_str
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")
    partition_cols = ast.literal_eval(args.partitions)
    documentation_bucket = args.documentation_bucket
    metadata_prefix = args.metadata_prefix

    bucket_suffix = (
        ".data.quintoandar.com.br"
        if env == "prod"
        else ".forno.data.quintoandar.com.br"
    )
    documentation_bucket = documentation_bucket + bucket_suffix

    logger.info(
        f"""m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, source={source},
        table_name={table_name}, execution_date_str={execution_date_str}, documentation_bucket={documentation_bucket}
        msg=Job execution started."""
    )

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
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

    documentation_df = get_tables_documentation_from_bucket(
        documentation_bucket, metadata_prefix, spark_client
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
        s3_path=f"{write_location}{write_table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader.update_metastore(
        documentation_df,
        write_database_name,
        write_table_name,
        format_options,
        write_location,
        partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=write_database_name,
        table_name=write_table_name,
        df=documentation_df,
        partition_cols=partition_cols,
    )
    spark_metastore_service.refresh_table(write_database_name, write_table_name)
