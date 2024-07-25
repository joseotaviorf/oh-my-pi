import json
import argparse
import os
from datetime import datetime, timedelta
from pyspark import Row
from pyspark.sql.types import StructType
from pyspark.sql.functions import current_timestamp, date_format, col, lit
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.base.api.api_enum import APIEnum
from quintoandar_hr_system_api_client.services import EndPointService
from quintoandar_hr_system_api_client.clients.hr_system_client import HrSystemClient
from quintoandar_hr_system_api_client.consumers import get_consumer

DATABRICKS_SCOPE = "people"
JOB_NAME = "load_hr_system_raw"
logger = QuintoAndarLogger(JOB_NAME)


def create_spark_dataframe(endpoint_id, json_data, spark_client, hr_system_client):
    spark_schema = EndPointService.get_spark_schema(endpoint_id, hr_system_client)
    schema = StructType.fromJson(spark_schema)
    return spark_client.create_dataframe(json_data, schema=schema)


def run_sync(endpoint_id, url, token, endpoint_details, spark_client):
    logger.info(f"m={JOB_NAME}, msg=Endpoint Details {endpoint_details}")
    hr_system_client = HrSystemClient(api_url=url, api_token=token)
    deduplication_key = endpoint_details.get("deduplication_key", None)
    endpoint_id = endpoint_id.replace("_", "").upper()
    consumer_instance = get_consumer(hr_system_client, endpoint_id)
    path = consumer_instance.path
    json_data = consumer_instance.sync(
        params=endpoint_details["params"], deduplication_key=deduplication_key
    )
    return create_spark_dataframe(path, json_data, spark_client, hr_system_client)


def insert_partitions(df, endpoint_details):
    column_to_partition = endpoint_details["column_to_partition"]
    df = df.withColumn("year", date_format(col(column_to_partition), "yyyy"))
    df = df.withColumn("month", date_format(col(column_to_partition), "MM"))
    df = df.withColumn("day", date_format(col(column_to_partition), "dd"))
    return df


def insert_columns(df, endpoint_details, has_dt_effective):
    df = df.withColumn("ts_load", current_timestamp())
    if has_dt_effective:
        dt_effective = endpoint_details["params"]["effectiveDate"]
        df = df.withColumn("dt_effective", lit(dt_effective.replace("-", "")))
    return df


def delete_columns(df, endpoint_details):
    spark.conf.set("spark.sql.caseSensitive", True)
    columns_to_delete = endpoint_details["columns_to_delete"]
    for column in columns_to_delete:
        df = df.drop(column)
    spark.conf.set("spark.sql.caseSensitive", False)
    return df


def load_raw(
    spark_client,
    df,
    environment,
    source,
    datalake_bucket,
    endpoint_id,
    partition_cols=None,
):
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    logger.info(
        f"m={JOB_NAME}, msg=Creating database in Spark Metastore if not exists..."
    )
    metastore_service = SparkMetastoreService(spark_client)
    metastore_service.create_database(database_name)
    s3_loader = S3Loader()
    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{endpoint_id}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=endpoint_id,
        format_options=format_options,
        force_recreate=True,
        database_location=database_location,
        partitions=partition_cols,
    )
    metastore_service.refresh_table(database_name, endpoint_id)


def pipeline_raw(
    spark_client,
    endpoint_id,
    url,
    token,
    endpoint_details,
    environment,
    source,
    datalake_bucket,
    partition_cols,
    has_dt_effective,
):
    df = run_sync(endpoint_id, url, token, endpoint_details, spark_client)
    if endpoint_details["has_columns_to_delete"]:
        df = delete_columns(df, endpoint_details)
    df = insert_columns(df, endpoint_details, has_dt_effective)
    if endpoint_details["has_partitions"]:
        df = insert_partitions(df, endpoint_details)
        load_raw(
            spark_client,
            df,
            environment,
            source,
            datalake_bucket,
            endpoint_id,
            partition_cols,
        )
    else:
        load_raw(spark_client, df, environment, source, datalake_bucket, endpoint_id)


def get_parser():
    parser = argparse.ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("endpoint_id", help="endpoint_id/name of the table")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument("partition_cols")
    parser.add_argument("endpoint_details")
    return parser


def define_offset(endpoint_details, offset, execution_date):
    days_offset = int(offset[0]) * offset[1]
    offset_date = execution_date + timedelta(days=days_offset)
    offset_date_str = offset_date.strftime("%Y-%m-%d")
    offset_details = endpoint_details.copy()
    offset_details["params"] = endpoint_details["params"].copy()
    offset_details["params"]["effectiveDate"] = offset_date_str
    return offset_date_str, offset_details


def clear_directory(
    datalake_bucket, source, endpoint_id, has_dt_effective, layer
):
    if has_dt_effective == True:
        dbutils.fs.rm(
            f"s3://{datalake_bucket}/{layer}/{source}/{endpoint_id}/",
            True
        )


def main():

    parser = get_parser()
    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    endpoint_id = args.endpoint_id
    execution_date_str = args.execution_date
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    if not isinstance(args.endpoint_details, dict):
        endpoint_details = json.loads(args.endpoint_details)

    if not isinstance(endpoint_details["params"], dict):
        endpoint_details["params"] = json.loads(endpoint_details["params"])

    if "expand" in endpoint_details:
        if not isinstance(endpoint_details["params"]["expand"], list):
            endpoint_details["params"]["expand"] = json.loads(endpoint_details["params"]["expand"])

    partition_cols = json.loads(args.partition_cols)
    has_dt_effective = endpoint_details.get("has_dt_effective", False)
    offsets = {
        (endpoint_details.get("future_offset", None), 1),
        (endpoint_details.get("past_offset", None), -1),
    }

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()
    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.HR_SYSTEM
    )
    credentials = json.loads(json_credentials)
    url = credentials["url"]
    token = credentials["token"]

    spark_client = SparkClient()
    logger.info(
        f"m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"table_name={endpoint_id}, msg=Starting spark job..."
    )

    if has_dt_effective == True:
        endpoint_details["params"]["effectiveDate"] = execution_date_str
    list_endpoint_details = {execution_date_str: endpoint_details}

    for offset in offsets:
        if offset[0] is not None:
            offset_date_str, offset_details = define_offset(
                endpoint_details, offset, execution_date
            )
            list_endpoint_details[offset_date_str] = offset_details

    clear_directory(
        datalake_bucket, source, endpoint_id, has_dt_effective, "raw"
    )
    for execution_date_str, endpoint_details in list_endpoint_details.items():
        logger.info(
            f"m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
            f"table_name={endpoint_id}, dt_effective={execution_date_str} msg=Getting data from API..."
        )
        pipeline_raw(
            spark_client,
            endpoint_id,
            url,
            token,
            endpoint_details,
            environment,
            source,
            datalake_bucket,
            partition_cols,
            has_dt_effective,
        )
    clear_directory(
        datalake_bucket, source, endpoint_id, has_dt_effective, "clean"
    )


if __name__ == "__main__":
    main()
