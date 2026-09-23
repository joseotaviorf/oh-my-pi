import ast
import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_jira_api_client.clients import JiraClient
from quintoandar_jira_api_client.consumers.jira_jql_consumer import JiraJQLConsumer
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.json_service import JsonService
from bietlejuice.services.metastore_services import MetastoreServiceFactory

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_dbutils():
    return BaseDBUtils().get_dbutils()


def build_updated_jql(load_start_date: str, load_end_date: str) -> str:
    return (
        f'updated >= "{load_start_date} 00:00" and updated <= "{load_end_date} 23:59"'
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("load_start_date", help="start execution date in str format")
    parser.add_argument("load_end_date", help="end execution date in str format")
    parser.add_argument("table_name")
    parser.add_argument("partitions", help="Partition columns name")
    parser.add_argument("endpoint_params", help="")

    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    partitions = ast.literal_eval(args.partitions)
    endpoint_params = json.loads(args.endpoint_params)
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date

    endpoint_enum = endpoint_params.get("endpoint_enum")

    dt_end_execution = datetime.strptime(load_end_date, "%Y-%m-%d").date()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, datalake_bucket={args.datalake_bucket}, source={args.source}, 
            table_name={args.table_name}, partitions={args.partitions}, endpoint_params={args.endpoint_params},
            load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, 
            msg=print spark jobs args"
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = get_dbutils().secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.JIRA
    )
    credentials = json.loads(json_credentials)

    jql_query_filter = build_updated_jql(load_start_date, load_end_date)

    params = {
        "jql": jql_query_filter,
        "fields": "*all",
        "expand": "changelog",
    }

    jira_client = JiraClient(
        username=credentials["username"],
        token=credentials["token"],
        server=credentials["server"],
    )

    consumer_instance = JiraJQLConsumer(jira_client)
    api_response = (
        consumer_instance.sync(endpoint_enum=endpoint_enum, params=params) or []
    )
    logger.info(
        f"m={JOB_NAME}, updated_window_issues={len(api_response)}, "
        "msg=loaded all issues updated in the execution window"
    )

    if not api_response:
        logger.warn(
            f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, 
            load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, 
            datalake_bucket={args.datalake_bucket}, table_name={args.table_name}, 
            params={params}, endpoint_enum={endpoint_enum}, 
            msg=result is empty"
        """
        )

    else:
        transformed_api_response = JsonService.transform_json_list_terms(api_response)
        spark_client = SparkClient()
        df = spark_client.create_dataframe(transformed_api_response)
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(dt_end_execution)
            .optimize_partition(200000)
            .output()
        )

        datalake_info = DatalakeMetastoreService.get_db_info(
            environment, source, datalake_bucket
        )
        spark_metastore_service = (
            MetastoreServiceFactory.create_loader_metastore_service(spark_client)
        )
        database_name = datalake_info["db_raw_databricks"]
        database_location = datalake_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        write_database_name, write_table_name, write_location = (
            resolve_datalake_write_target(
                prod_database=database_name,
                prod_table=table_name,
                prod_location=database_location,
                bucket=datalake_bucket,
                target_database=args.target_database_name,
                target_table=args.target_table_name,
            )
        )
        spark_metastore_service.create_database(write_database_name)

        # loaders
        s3_loader = S3Loader()
        s3_loader.load_incremental_table(
            df=df,
            database_name=write_database_name,
            table_name=write_table_name,
            format_options=format_options,
            database_location=write_location,
            partition_cols=partitions,
        )

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df,
            write_database_name,
            write_table_name,
            format_options,
            write_location,
            partitions,
            force_recreate=False,
        )
        spark_metastore_service.create_new_partitions_from_df(
            database_name=write_database_name,
            table_name=write_table_name,
            df=df,
            partition_cols=partitions,
        )
        spark_metastore_service.refresh_table(write_database_name, write_table_name)
