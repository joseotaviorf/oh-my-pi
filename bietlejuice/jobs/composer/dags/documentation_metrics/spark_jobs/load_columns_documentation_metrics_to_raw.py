import logging
from argparse import ArgumentParser
from datetime import datetime

import boto3
import yaml
from pyspark.sql import Row
from pyspark.sql.functions import udf, lit, explode_outer, map_keys, map_values
from pyspark.sql.types import StructType, StructField, StringType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.base.spark import (
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_columns_documentation_metrics_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


# ################################  Metastore Data  ##################################
# TODO: these functions could be in a common place instead of copy-pasted between the following jobs:
# - load_lineage_and_tags_metrics_to_raw
# - load_columns_documentation_metrics_to_raw
# - load_tables_documentation_metrics_to_raw


def get_columns_from_metastore(spark_client, schemas_skip_list):
    final_df = get_empty_df(spark_client)
    databases = list_metastore_databases(spark_client, schemas_skip_list)

    for database in databases:
        tables = list_metastore_tables(spark_client, database)
        for table in tables:
            columns_df = (
                spark_client.get_records(f"SHOW COLUMNS IN {database}.{table}")
                .withColumn("database_name", lit(database))
                .withColumn("table_name", lit(table))
            )
            final_df = final_df.union(columns_df)

    final_df = final_df.coalesce(4)  # reducing number of partitions
    udf_extract_layer = udf(extract_layer_from_database_name)
    final_df = final_df.withColumn("layer", udf_extract_layer("database_name"))

    return final_df


def get_empty_df(spark_client):
    df_schema = StructType(
        [
            StructField("column_name", StringType(), True),
            StructField("database_name", StringType(), True),
            StructField("table_name", StringType(), True),
        ]
    )
    return spark_client.create_dataframe([], df_schema)


def list_metastore_databases(spark_client, schemas_skip_list):
    databases_df = (
        spark_client.get_records("SHOW DATABASES")
        .where("databaseName not like '%_staging%'")
        .collect()
    )
    databases = [
        db.databaseName
        for db in databases_df
        if db.databaseName not in schemas_skip_list
    ]
    return databases


def list_metastore_tables(spark_client, database):
    tables_df = (
        spark_client.get_records(f"SHOW TABLES IN {database}")
        .where("isTemporary = false")
        .drop("isTemporary")
        .collect()
    )
    return [tb.tableName for tb in tables_df]


def extract_layer_from_database_name(database_name):
    if database_name.startswith("dw_"):
        return LayerEnum.DW.value
    elif database_name.startswith("datalake_"):
        if database_name.endswith("_raw"):
            return LayerEnum.RAW.value
        if database_name.endswith("_clean"):
            return LayerEnum.CLEAN.value
        else:
            return LayerEnum.ENRICH.value
    return ""


# ####################################  S3 Data  ######################################


def get_documentation_from_bucket(bucket, prefix, migrated_databases, spark_client):
    s3_client = boto3.client("s3")
    documentation_paths = get_documentation_paths_from_bucket(bucket, prefix, s3_client)
    documentation_contents = get_content_from_paths(
        bucket, documentation_paths, migrated_databases, s3_client
    )
    documentation_df = create_dataframe_from_contents(
        documentation_contents, spark_client
    )
    documentation_df = documentation_df.coalesce(4)  # reducing number of partitions

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


def get_content_from_paths(bucket, documentation_paths, migrated_databases, s3_client):
    s3_objects = []
    for file_path in documentation_paths:
        file_object = s3_client.get_object(Bucket=bucket, Key=file_path)
        s3_objects.append(file_object["Body"])

    documentation_contents = []
    for obj in s3_objects:
        documentation_contents.append(yaml.safe_load(obj))

    for doc in documentation_contents:
        doc["database_name"] = add_prefix_to_migrated_databases(
            doc["database_name"], migrated_databases
        )

    return documentation_contents


def add_prefix_to_migrated_databases(database_name, migrated_databases):
    if database_name in migrated_databases:
        return f"dw_{database_name}"
    return database_name


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

    # Creates final columns and drops useless fields
    documentation_df = (
        documentation_df.withColumn(
            "description", documentation_df.column_doc["description"]
        )
        .withColumn(
            "joins_with_column", documentation_df.column_doc["joins_with_column"]
        )
        .withColumnRenamed("name", "table_name")
        .drop("owner")
        .drop("columns")
        .drop("column")
        .drop("column_doc")
    )
    return documentation_df


# ################################  Comparison  ##################################


def compare_documentation_with_metastore(
    documentation_data, metastore_data, spark_client
):
    documentation_data.createOrReplaceTempView("vw_documentation")
    metastore_data.createOrReplaceTempView("vw_metastore")

    query = f"""
        SELECT
            ms.layer,
            ms.database_name,
            ms.table_name,
            ms.column_name,
            COALESCE(doc.description != '', FALSE) AS has_description,
            COALESCE(doc.joins_with_column != '', FALSE) AS has_joins_with_column
        FROM
            vw_metastore AS ms
        LEFT JOIN
            vw_documentation AS doc
                ON ms.database_name = doc.database_name
                AND ms.table_name = doc.table_name
                AND ms.column_name = doc.column_name
    """

    return spark_client.get_records(query)


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
    migrated_databases = config_service.get_config("DATABASES_MIGRATED_TO_COMPOSER")
    schemas_skip_list = config_service.get_config("DATABASE_SKIP_LIST")
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
    metastore_columns_df = get_columns_from_metastore(spark_client, schemas_skip_list)
    documentation_df = get_documentation_from_bucket(
        documentation_bucket, documentation_prefix, migrated_databases, spark_client
    )
    documentation_metrics_df = compare_documentation_with_metastore(
        documentation_df, metastore_columns_df, spark_client
    )
    documentation_metrics_df = (
        SparkDataFrameService()
        .input(documentation_metrics_df)
        .create_year_month_day_columns_from_date(execution_date)
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )

    # loaders
    s3_loader.load_df(
        df=documentation_metrics_df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader.update_metastore(
        documentation_metrics_df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=documentation_metrics_df,
        partition_cols=partition_cols,
    )
    spark_metastore_service.refresh_table(database_name, table_name)
