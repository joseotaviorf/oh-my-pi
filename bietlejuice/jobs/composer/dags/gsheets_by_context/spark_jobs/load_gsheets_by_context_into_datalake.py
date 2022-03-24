import logging
import json

from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from quintoandar_gsheets_api_client.clients import GoogleSheetsClient

from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.formatters import StringFormatter
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

from pyspark.sql import functions
from pyspark.sql.types import StructField, StructType, StringType

JOB_NAME = "load_gsheets_by_context_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def __columns_to_alphanumeric_snake_case(df):
    """
    This method applies changes to dataframe column names.
    @param df: dataframe with google sheets data.
    @return: dataframe
    """
    old_columns = df.columns
    new_columns = [
        StringFormatter.set_alphanumeric_snake_case(column) for column in old_columns
    ]
    return df.toDF(*new_columns)


def __generate_schema(data):
    """
    This method creates the schema from the data returned by the API.
    @param data: list with data returned by the API.
    @return: StructType
    """
    if len(data):
        columns = data[0].keys()
        type_array = [StructField(column_name, StringType()) for column_name in columns]
        schema = StructType(type_array)
        return schema

    raise ValueError(f"m=__generate_schema, msg=Table {table_name} Empty!")


def __get_auth(dbutils):
    """
    This method gets credentials from the Gsheets API.
    @param dbutils: DBUtils.
    @return: dict and str
    """
    credentials = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.GSHEETS_CREDENTIALS)
    )
    scope = credentials.pop("scope")
    return credentials, scope


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name", help="table name to insert into datalake")
    parser.add_argument("sheet_details", help="gsheets sheet name and sheet id")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    sheet_details = json.loads(args.sheet_details)
    partitions_cols = ["year", "month", "day"]

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name}, execution_date=execution_date msg=Starting spark job...
        """
    )

    # Initializing GoogleSheetsClient
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials, scope = __get_auth(dbutils)

    client = GoogleSheetsClient(credentials, scope)

    # Initializing clients
    spark_client = SparkClient()

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    spark_metastore_service = SparkMetastoreService(spark_client)
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    database_location = datalake_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")

    # API response
    client_response = client.get_data_from_sheet(
        sheet_details["sheet_name"], sheet_details["sheet_id"]
    )
    schema = __generate_schema(client_response)

    df = spark_client.create_dataframe(client_response, schema=schema)

    df = __columns_to_alphanumeric_snake_case(df)

    df = df.withColumn("ts_load", functions.current_timestamp())

    if sheet_details.get("partitioned"):
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
        partitions=partitions_cols if sheet_details.get("partitioned") else None,
    )

    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )

    logger.info(
        f"""
            m={JOB_NAME}, table_name={table_name}, msg=sheet successfully loaded!"
        """
    )
