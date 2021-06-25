import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from quintoandar_chattermill_api_client.clients import ChattermillClient

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("endpoints", help="name of the endpoints")
    parser.add_argument("execution_date", help="execution date in str format")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, endpoints={args.endpoints},
            execution_date={args.execution_date}, datalake_bucket={args.datalake_bucket}, msg=print spark jobs args"
        """
    )

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    endpoints = args.endpoints
    endpoints = endpoints.split(",")
    execution_date = args.execution_date
    execution_date = execution_date.replace("-", "")
    partition_cols = ["year", "month", "day"]

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.CHATTERMILL
    )
    credentials = json.loads(json_credentials)
    chattermill_client = ChattermillClient(
        project_name=credentials["project_name"], auth=credentials["auth"]
    )

    spark_client = SparkClient()

    for endpoint in endpoints:
        api_response = chattermill_client.get_data(
            endpoint=endpoint, from_date=execution_date
        )

        for row in api_response:
            if "user_attributes" in row:
                row["user_attributes"] = json.dumps(row.get("user_attributes"))
            if "tags" in row:
                row["tags"] = json.dumps(row.get("tags"))
            if "phrases" in row:
                row["phrases"] = json.dumps(row.get("phrases"))

        if api_response:
            df = spark_client.create_dataframe(api_response)
            dt_execution = datetime.strptime(execution_date, "%Y%m%d")
            df = df.coalesce(1)
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(dt_execution)
                .output()
            )

            datalake_info = DatalakeMetastoreService.get_db_info(
                environment, source, datalake_bucket
            )
            spark_metastore_service = SparkMetastoreService(spark_client)
            database_name = datalake_info["db_raw_databricks"]
            spark_metastore_service.create_database(database_name)

            database_location = datalake_info["db_raw_path"]
            format_options = SparkTableStorageFormat.DEFAULT_RAW
            table_name = endpoint

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
                partition_cols,
                force_recreate=False,
            )
            spark_metastore_service.create_new_partitions_from_df(
                database_name=database_name,
                table_name=table_name,
                df=df,
                partition_cols=partition_cols,
            )
            spark_metastore_service.refresh_table(database_name, table_name)
