import json
import argparse
from pyspark.sql.types import StructType
from pyspark.sql.functions import current_timestamp, date_format, col
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.base.api.api_enum import APIEnum
from quintoandar_workable_api_client.clients import WorkableClient
from quintoandar_workable_api_client.consumers import CONSUMERS
from quintoandar_workable_api_client.constants import EndpointEnum

DATABRICKS_SCOPE = "people"
JOB_NAME = "load_workable_to_raw"
logger = QuintoAndarLogger(JOB_NAME)


def run_sync(endpoint, token, start_time=None, params=None):
    endpoint_enum = EndpointEnum.get_endpoint(endpoint.upper())
    consumer = endpoint_enum["consumer"]
    client = WorkableClient(api_token=token)
    consumer_instance = CONSUMERS[consumer](client, endpoint_enum)
    return consumer_instance.sync(start_time=start_time, params=params)


def insert_partitions(df, column_to_partition):
    df = df.withColumn("year", date_format(col(column_to_partition), "yyyy"))
    df = df.withColumn("month", date_format(col(column_to_partition), "MM"))
    df = df.withColumn("day", date_format(col(column_to_partition), "dd"))
    return df


def insert_columns(df):
    df = df.withColumn("ts_load", current_timestamp())
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


def get_args():
    parser = argparse.ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="endpoint_id/name of the table")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument("extraction_type", help="type of extraction")
    parser.add_argument("partitions", help="columns to partition")
    parser.add_argument("extra_config", help="workable api token")
    return parser.parse_args()


def get_credentials(dbutils):
    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.WORKABLE)
    credentials = json.loads(json_credentials)
    token = credentials["token"]
    return token

if __name__ == "__main__":
    args = get_args()
    environment = args.environment
    datalake_bucket = args.bucket
    source = args.source
    endpoint = args.table_name
    execution_date_str = args.execution_date
    extraction_type = args.extraction_type
    partition_cols = json.loads(args.partitions)
    extra_config = json.loads(args.extra_config)
    partition_by = extra_config.get("partition_by", None)
    params = json.loads(extra_config.get("params", '{"limit": 100}'))

    spark_client = SparkClient()
    logger.info(
        f"m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"table_name={endpoint}, msg=Starting spark job..."
    )

    token = get_credentials(dbutils)
    start_time = execution_date_str if extraction_type == "incremental" else None
    json_data = run_sync(endpoint=endpoint, token=token, start_time=start_time, params=params)
    endpoint_schema = EndpointEnum.get_endpoint(endpoint.upper())["schema"]
    schema = StructType.fromJson(endpoint_schema)
    df = spark_client.create_dataframe(json_data, schema=schema)
    df = insert_columns(df)
    if len(partition_cols) > 0:
        df = insert_partitions(df, partition_by)
    else:
        partition_cols = None
    load_raw(
        spark_client,
        df,
        environment,
        source,
        datalake_bucket,
        endpoint,
        partition_cols,
    )
