from typing import List, Dict, Any, Set

import boto3
import logging
import json
import ast

from json.decoder import JSONDecodeError

from datetime import datetime
from argparse import ArgumentParser

from botocore.client import BaseClient
from pyspark.sql import Row, DataFrame
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_metrics_registration_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_metrics_paths_from_bucket(
    bucket: str, prefix: str, s3_client: BaseClient
) -> List[str]:
    pages = s3_client.get_paginator("list_objects_v2").paginate(
        Bucket=bucket, Prefix=prefix
    )

    bucket_objects = []
    for page in pages:
        bucket_objects.extend(page["Contents"])

    documentation_paths = [
        obj["Key"] for obj in bucket_objects if "metrics/" in obj["Key"]
    ]

    return documentation_paths


def get_content_from_paths(bucket, paths, s3_client) -> List[Dict[str, Any]]:
    contents = []
    for file_path in paths:
        file_object = s3_client.get_object(Bucket=bucket, Key=file_path)
        try:
            contents.append(json.load(file_object["Body"]))
        except JSONDecodeError:
            logger.info(f"skipping {file_path}")
    return contents


def fill_all_cols(
    content: Dict[str, any], metric_cols: Set[str], execution_date: datetime
) -> Dict[str, Any]:
    """
    Some metrics don't have all fields. This function makes sure all columns exist in the dict
    :param content: the content of a metric file loaded from S3
    :type content: Dict[str, any]
    :param metric_cols: List with all required columns for a metric
    :type metric_cols: Set[str]
    :param execution_date: the spark job execution date
    :type execution_date: datetime
    :return: Dict with a metric with all columns filled
    :rtype: Dict
    """
    metric_data = {col: content.get(col) for col in metric_cols}
    metric_data["ts_load"] = execution_date
    return metric_data


def get_metrics_df(
    bucket: str,
    prefix: str,
    spark_client: SparkClient,
    metric_cols: Set[str],
    execution_date: datetime,
) -> DataFrame:
    s3_client = boto3.client("s3")
    metrics_paths = get_metrics_paths_from_bucket(bucket, prefix, s3_client)
    metrics_content = get_content_from_paths(bucket, metrics_paths, s3_client)

    metrics_with_all_cols = [
        fill_all_cols(content, metric_cols, execution_date)
        for content in metrics_content
    ]

    metric_df = spark_client.create_dataframe(
        Row(**doc) for doc in metrics_with_all_cols
    )
    return metric_df


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str)
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("source", type=str)
    parser.add_argument("table_name", type=str)
    parser.add_argument("execution_date_str", type=str)
    parser.add_argument("metrics_bucket",type=str)
    parser.add_argument("metrics_path",type=str)
    parser.add_argument('partition_cols',type= str)
    parser.add_argument('metric_cols',type= str)

    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date_str = args.execution_date_str
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")
    metrics_bucket = args.metrics_bucket
    metrics_path = args.metrics_path
    partition_cols = ast.literal_eval(args.partition_cols)
    metric_cols = ast.literal_eval(args.metric_cols)

    bucket_suffix = ".data.quintoandar.com.br" if env == "prod" else ".forno.data.quintoandar.com.br"
    metrics_bucket = metrics_bucket + bucket_suffix

    logger.info(
        f"""m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, source={source},
        table_name={table_name}, execution_date_str={execution_date_str}, metrics_bucket={metrics_bucket},
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
    spark_metastore_service.create_database(database_name)

    # Creating metrics dataframe
    metrics_df = get_metrics_df(
        metrics_bucket, metrics_path, spark_client, metric_cols, execution_date
    )
    metrics_df = (
        SparkDataFrameService()
        .input(metrics_df)
        .create_year_month_day_columns_from_date(execution_date)
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )

    # loaders
    s3_loader.load_df(
        df=metrics_df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader.update_metastore(
        metrics_df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=metrics_df,
        partition_cols=partition_cols,
    )
    spark_metastore_service.refresh_table(database_name, table_name)
