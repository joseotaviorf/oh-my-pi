import json
import logging
import re

from unidecode import unidecode

from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from quintoandar_gsheets_api_client.clients import GoogleSheetsClient

from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat, BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader

from pyspark.sql.types import StructField, StructType, StringType

JOB_NAME = "load_gsheets_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def __columns_to_snake_case(df):
    old_columns = df.columns
    new_columns = [__format_column_name(column) for column in old_columns]
    return df.toDF(*new_columns)


def __format_column_name(column_name):
    alphanumeric_column_name = re.sub(r"[^\w\s]", "", column_name)
    snake_cased_column_name = re.sub(r"\s+", "_", alphanumeric_column_name)
    no_accents_column_name = unidecode(snake_cased_column_name)
    return no_accents_column_name.lower()


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


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("target", help="name of the target")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("table_name", help="table name to insert into datalake")
    parser.add_argument("sheet_details", help="gsheets sheet name and sheet id")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.target},
            datalake_bucket={args.datalake_bucket}, msg=print spark jobs args"
        """
    )

    environment = args.environment
    target = args.target
    datalake_bucket = args.datalake_bucket

    table_name = args.table_name
    sheet_details = json.loads(args.sheet_details)

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials, scope = __get_auth(dbutils)

    client = GoogleSheetsClient(credentials, scope)

    spark_client = SparkClient()

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, target, datalake_bucket
    )
    spark_metastore_service = SparkMetastoreService(spark_client)
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    database_location = datalake_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    client_response = client.get_data_from_sheet(
        sheet_details["sheet_name"], sheet_details["sheet_id"]
    )

    schema = __generate_schema(client_response)

    df = spark_client.create_dataframe(client_response, schema=schema)

    df = __columns_to_snake_case(df)

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
