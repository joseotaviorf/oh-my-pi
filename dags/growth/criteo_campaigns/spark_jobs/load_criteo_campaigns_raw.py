import json

from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from quintoandar_criteo_api_client.clients import CriteoClient

from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_criteo_campaigns_raw"

logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")

    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date

    config_service = ConfigurationService(source)
    table_name = config_service.get_config("table_name")
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    request_headers = config_service.get_config("request_headers")
    request_body = config_service.get_config("request_body")
    request_body["startDate"] = load_start_date
    request_body["endDate"] = load_end_date

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials_str = dbutils.secrets.get(scope="quintoandar", key=APIEnum.CRITEO)
    credentials = json.loads(credentials_str)

    criteo_client = CriteoClient(
        client_id=credentials["client_id"], client_secret=credentials["client_secret"]
    )
    api_response = criteo_client.get_data(request_body, request_headers)
    api_response = [
        {f"{k[0].upper()}{k[1:]}": v for k, v in res.items()} for res in api_response
    ]

    if api_response:
        spark_client = SparkClient()
        df = spark_client.create_dataframe(api_response)
        df = df.withColumnRenamed("Day", "AttributionDate")

        datalake_info = DatalakeMetastoreService.get_db_info(
            environment, source, datalake_bucket
        )
        spark_metastore_service = SparkMetastoreService(spark_client)
        database_name = datalake_info["db_raw_databricks"]
        spark_metastore_service.create_database(database_name)

        database_location = datalake_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        # loaders
        s3_loader = S3Loader()
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=raw_partition_cols,
        )
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            raw_partition_cols,
            force_recreate=True,
        )
        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=raw_partition_cols,
        )
