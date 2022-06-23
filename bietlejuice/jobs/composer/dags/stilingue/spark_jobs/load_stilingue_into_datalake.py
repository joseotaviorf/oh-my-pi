import json
import logging
from argparse import ArgumentParser
from datetime import datetime
from pyspark.sql import types, functions

from quintoandar_logger import QuintoAndarLogger
from quintoandar_stilingue_api_client.clients.stilingue_client import StilingueClient
from quintoandar_stilingue_api_client.consumers.stilingue_consumer import (
    StilingueConsumer,
)
from quintoandar_stilingue_api_client.constants.endpoint_enum import EndpointEnum

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_stilingue_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="raw table name")
    parser.add_argument("execution_date")
    parser.add_argument("table_details", help="clean table name and API params")
    parser.add_argument("endpoint_schema_exceptions", help="endpoint enum expections")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name

    dt_execution = datetime.strptime(args.execution_date, "%Y-%m-%d")
    table_details = json.loads(args.table_details)
    endpoint_schema_exceptions = json.loads(args.endpoint_schema_exceptions)

    api_params = table_details.get("api_params")
    partition_cols = table_details.get("partition_cols")

    if api_params and api_params.get("date_range"):
        api_params["date_range"] = api_params["date_range"].format(
            year=dt_execution.strftime("%Y"),
            month=dt_execution.strftime("%m"),
            day=dt_execution.strftime("%d"),
        )

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
            source={source}, table_name={table_name}, msg=print spark jobs args"
        """
    )

    # Initializing StilingueClient
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.STILINGUE
    )

    credentials = json.loads(json_credentials)

    stilingue_client = StilingueClient()
    consumer = StilingueConsumer(
        api_token=credentials["api_token"], client=stilingue_client
    )

    # Initializing clients
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    database_name = datalake_info["db_raw_databricks"]
    database_location = datalake_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")

    # API response
    endpoint_details = EndpointEnum[table_details.get("api_endpoint")]

    response = consumer.sync(response_params=endpoint_details.value, params=api_params)

    if response:
        schema = types.StructType.fromJson(
            consumer.formatting_data_schema(
                endpoint_schema_exceptions.get(endpoint_details.name)
                or list(response[0].keys())
            )
        )

        df = spark_client.create_dataframe(data=response, schema=schema)

        df = df.withColumn("ts_load", functions.lit(dt_execution))
        if partition_cols:
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column("ts_load")
                .output()
            )

        # loaders
        s3_loader = S3Loader()
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            partitions=partition_cols or [],
            force_recreate=False,
        )

        if partition_cols:
            spark_metastore_service.create_new_partitions_from_df(
                database_name=database_name,
                table_name=table_name,
                df=df,
                partition_cols=partition_cols,
            )

        spark_metastore_service.refresh_table(database_name, table_name)
