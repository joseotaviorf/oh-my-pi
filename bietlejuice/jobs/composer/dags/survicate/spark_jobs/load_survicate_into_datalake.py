import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from quintoandar_logger import QuintoAndarLogger
from quintoandar_survicate_api_client.consumers import CONSUMERS
from quintoandar_survicate_api_client.clients import SurvicateClient

JOB_NAME = "load_survicate_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

SCHEMA = """
    id STRING,
    custom_attributes STRUCT<
        ticket_id: STRING
    >,
    first_seen_date STRING,
    first_response_date STRING,
    answers ARRAY<
        STRUCT<
            survey_point: STRUCT<
                id: STRING,
                type: STRING,
                pretty_type: STRING,
                answer_type: STRING
            >,
            question: STRING,
            content: STRING
        >
    >,
    page_url STRING,
    visitor_id STRING,
    visitor_uuid STRING,
    response_uuid STRING
"""


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = args.execution_date
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partition_cols = ["year", "month", "day"]
    table_name = "surveys"

    logger.info(
        f"m={JOB_NAME}, "
        f"environment={environment}, "
        f"source={source}, "
        f"datalake_bucket={datalake_bucket}, "
        f"msg=Spark job arguments"
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )

    file_type = SparkTableStorageFormat.DEFAULT_RAW
    filesystem_path = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    api_token_object = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.SURVICATE)
    )
    api_token = api_token_object["api_token"]

    sirena_client = SurvicateClient(api_token=api_token)
    survey_list_consumer = CONSUMERS["survey_list"](sirena_client)
    survey_response_consumer = CONSUMERS["survey_response"](sirena_client)

    survey_ids = survey_list_consumer.sync(flattened_key="id")
    results = survey_response_consumer.sync(execution_date, survey_ids)

    if results:
        df = spark_client.create_dataframe(results, schema=SCHEMA)

        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(dt_execution)
            .output()
        )

        # loaders
        s3_loader.load_incremental_table(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=file_type,
            database_location=filesystem_path,
            partition_cols=partition_cols,
        )
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            file_type,
            filesystem_path,
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
