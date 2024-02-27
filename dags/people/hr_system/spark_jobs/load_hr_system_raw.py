import json
import argparse
import os
from pyspark import Row
from pyspark.sql.types import StructType
from pyspark.sql.functions import current_timestamp, date_format, col
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
JOB_NAME = "load_hr_system_to_raw"
logger = QuintoAndarLogger(JOB_NAME)


def create_spark_dataframe(endpoint_id, json_data, spark_client, hr_system_client):
    spark_schema = EndPointService.get_spark_schema(endpoint_id, hr_system_client)
    schema = StructType.fromJson(spark_schema)
    return spark_client.create_dataframe(json_data, schema=schema)


def run_sync(endpoint_id, url, token, endpoint_details):
    hr_system_client = HrSystemClient(api_url=url, api_token=token)
    endpoint_params = endpoint_details["params"]
    deduplication_key = endpoint_details.get("deduplication_key", None)
    endpoint_id = endpoint_id.replace("_", "").upper()
    consumer_instance = get_consumer(hr_system_client, endpoint_id)
    path = consumer_instance.path
    json_data = consumer_instance.sync(params=endpoint_params, deduplication_key=deduplication_key)
    return create_spark_dataframe(path, json_data, spark_client, hr_system_client)


def insert_columns(df, endpoint_details):
    column_to_partition = endpoint_details["column_to_partition"]
    df = df.withColumn("ts_load", current_timestamp())
    df = df.withColumn("year", date_format(col(column_to_partition), "yyyy"))
    df = df.withColumn("month", date_format(col(column_to_partition), "MM"))
    df = df.withColumn("day", date_format(col(column_to_partition), "dd"))
    return df

def delete_columns(df, endpoint_details):
  spark.conf.set('spark.sql.caseSensitive', True)
  columns_to_delete = endpoint_details['columns_to_delete']
  for column in columns_to_delete:
      df = df.drop(column)
  spark.conf.set('spark.sql.caseSensitive', False)
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("endpoint_id", help="endpoint_id/name of the table")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument("partition_cols")
    parser.add_argument("endpoint_details")
    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    endpoint_id = args.endpoint_id
    execution_date = args.execution_date
    partition_cols = json.loads(args.partition_cols)
    endpoint_details = json.loads(args.endpoint_details)

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
    df = run_sync(endpoint_id, url, token, endpoint_details)
    if endpoint_details['has_columns_to_delete']:
        df = delete_columns(df, endpoint_details)
    if endpoint_details["has_partitions"]:
        df = insert_columns(df, endpoint_details)
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
        df = df.withColumn("ts_load", current_timestamp())
        load_raw(spark_client, df, environment, source, datalake_bucket, endpoint_id)
