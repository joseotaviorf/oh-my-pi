import boto3
import json
import os
import pyspark.sql.functions as F
import re
from argparse import ArgumentParser, Namespace
from bietlejuice import BIETLEJUICE_PROJECT_ROOT
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseSparkContext, SparkTableStorageFormat
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline import IncrementalTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService
from datetime import datetime
from hierarchical_conf.hierarchical_conf import HierarchicalConf
from pyspark.sql.dataframe import DataFrame
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_table_usage_in_queries"
REGEX_TABLE_PATTERN_IN_SQL = r"(?i)(?:FROM|JOIN)\s*(`?\w+`?\.`?\w+`?)"
logger = QuintoAndarLogger(JOB_NAME)


def main() -> None:
    args = parse_arguments()
    query_files_bucket, query_files_prefix = get_query_bucket_and_prefix_in_s3()

    query_files, query_modified_dates = read_all_files_with_prefix(query_files_bucket, query_files_prefix)
    tables_per_query = find_tables_in_queries(query_files)
    df_table_usage_in_queries = generate_dataframe(tables_per_query, query_modified_dates)
    final_df = generate_relevant_columns(
        df_table_usage_in_queries, datetime.strptime(args.execution_date, "%Y-%m-%d")
    )
    load_table(
        final_df,
        args.env,
        args.schema,
        args.table_name,
        args.datalake_bucket,
        json.loads(args.partitions),
    )


def get_query_bucket_and_prefix_in_s3() -> tuple[str, str]:
    """Returns, respectively, the bucket and prefix in S3 where the queries are stored."""

    global_confs = HierarchicalConf([BIETLEJUICE_PROJECT_ROOT])
    query_files_bucket = global_confs.get_config("databricks_bucket")
    dags_packages_files_prefix = global_confs.get_config(
        "dags_packages_files_path_in_s3"
    )
    query_files_prefix = os.path.join(dags_packages_files_prefix, "queries/")
    return query_files_bucket, query_files_prefix


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("execution_date")
    parser.add_argument("partitions")
    args = parser.parse_args()
    logger.info(
        f"env={args.env}, datalake_bucket={args.datalake_bucket}, schema={args.schema}, table_name={args.table_name}, execution_date={args.execution_date}, partitions={args.partitions}"
    )
    return args


def read_all_files_with_prefix(bucket: str, prefix: str) -> tuple[dict[str, str], dict[str, datetime]]:
    """
    Returns a tuple of:
    - a dictionary in which the key is the object key, and the value is the object content.
    - a dictionary in which the key is the object key, and the value is a datetime of the last modified date.
    """
    logger.info(f"Reading all files with prefix '{prefix}' from bucket '{bucket}'")
    s3 = boto3.client("s3")
    paginator = s3.get_paginator("list_objects_v2")
    pages = paginator.paginate(Bucket=bucket, Prefix=prefix)
    file_contents = {}
    file_modified_dates = {}
    for page in pages:
        for obj in page["Contents"]:
            key = obj["Key"]
            response = s3.get_object(Bucket=bucket, Key=key)
            file_contents[key.replace(prefix, "")] = (
                response["Body"].read().decode("utf-8")
            )
            file_modified_dates[key.replace(prefix, "")] = obj["LastModified"]
    return file_contents, file_modified_dates


def find_tables_in_queries(queries: dict[str, str]) -> dict[str, list[str]]:
    logger.info(f"Finding tables in {len(queries)} queries")
    tables_per_query = {}
    for query_path, query in queries.items():
        tables_per_query[query_path] = find_tables_in_query(query)
    return tables_per_query


def find_tables_in_query(query: str) -> list[str]:
    return list({t.lower().replace("`", "") for t in re.findall(REGEX_TABLE_PATTERN_IN_SQL, query)})


def generate_dataframe(tables_per_query: dict[str, list[str]], query_modified_dates: dict[str, datetime]) -> DataFrame:
    logger.info(f"Generating dataframe")
    values = []
    for query_path, tables in tables_per_query.items():
        for table in tables:
            values.append((query_path, table, query_modified_dates[query_path]))
    columns = ["query_path", "used_table", "query_last_modified"]
    return BaseSparkContext.spark.createDataFrame(values, columns)


def generate_relevant_columns(df: DataFrame, execution_date: datetime) -> DataFrame:
    return df.withColumns(
        {
            "query_table_name": F.expr(
                "SPLIT_PART(ELEMENT_AT(SPLIT(query_path, '/'), -1), '.', 1)"
            ),
            "query_dag_name": F.expr("SPLIT_PART(query_path, '/', 1)"),
            "query_layer": F.expr("SPLIT_PART(query_path, '/', 2)"),
            "year": F.lit(execution_date.year),
            "month": F.lit(execution_date.month),
            "day": F.lit(execution_date.day),
        }
    )


def load_table(
    df: DataFrame,
    environment: str,
    schema: str,
    table_name: str,
    datalake_bucket: str,
    partitions: list,
) -> None:
    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    IncrementalTableLoaderPipeline(
        database_name,
        table_name.lower(),
        database_location,
        LayerEnum.RAW,
        None,
        partitions,
    ).load_and_register(df, format_options)


if __name__ == "__main__":
    main()
