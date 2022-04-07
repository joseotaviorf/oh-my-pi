import json
import logging
import time

from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from quintoandar_gsheets_api_client.clients import GoogleSheetsClient

from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat, BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.formatters import StringFormatter

from pyspark.sql.types import StructField, StructType, StringType

JOB_NAME = "load_gsheets_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def __columns_to_alphanumeric_snake_case(df):
    old_columns = df.columns
    new_columns = [
        StringFormatter.set_alphanumeric_snake_case(column) for column in old_columns
    ]
    return df.toDF(*new_columns)


def __generate_schema(data):

    if len(data):
        columns = data[0].keys()
        type_array = [StructField(column_name, StringType()) for column_name in columns]
        schema = StructType(type_array)
        return schema

    raise ValueError(f"m=__generate_schema, msg=Table {table_name} Empty!")


def __get_auth(dbutils):
    credentials = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.GSHEETS_CREDENTIALS)
    )
    scope = credentials.pop("scope")
    return credentials, scope


def __preload_gsheet(sheet_details):
    """
    This method makes an API call to preload the gsheet, and then waits the amount of seconds
    specified by sheet_details['preload_time_in_seconds']
    @param sheet_details: dict
    """
    preload_client_response = client.get_data_from_sheet(
        sheet_details["sheet_name"], sheet_details["sheet_id"]
    )
    logger.info(
        f"""
        m=__preload_gsheet, msg=Initial length of {len(preload_client_response)}. Waiting for
        {sheet_details["preload_time_in_seconds"]} seconds to preload the gsheet {sheet_details["sheet_name"]}"
    """
    )
    time.sleep(sheet_details["preload_time_in_seconds"])


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="table name to insert into datalake")
    parser.add_argument(
        "sheet_details",
        help="gsheets sheet name, sheet id, and (optional) preload time in seconds",
    )

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source},
            datalake_bucket={args.datalake_bucket}, msg=print spark jobs args"
        """
    )

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    sheet_details = json.loads(args.sheet_details)

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials, scope = __get_auth(dbutils)

    client = GoogleSheetsClient(credentials, scope)

    spark_client = SparkClient()

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    spark_metastore_service = SparkMetastoreService(spark_client)
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    database_location = datalake_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    if "preload_time_in_seconds" in sheet_details:
        __preload_gsheet(sheet_details)

    client_response = client.get_data_from_sheet(
        sheet_details["sheet_name"], sheet_details["sheet_id"]
    )

    schema = __generate_schema(client_response)

    df = spark_client.create_dataframe(client_response, schema=schema)

    df = __columns_to_alphanumeric_snake_case(df)

    # loaders
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader.load_df(
        df=df, s3_path=f"{database_location}{table_name}", format_options=format_options
    )
    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )

    logger.info(
        f"""
            m={JOB_NAME}, table_name={table_name}, msg=sheet successfully loaded!"
        """
    )
