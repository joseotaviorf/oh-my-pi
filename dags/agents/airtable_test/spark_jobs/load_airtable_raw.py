import json
import logging
import ast

from argparse import ArgumentParser
from datetime import datetime, timedelta
from pyspark.sql.types import StructType, StructField, StringType

from quintoandar_airtable_api_client.clients import AirtableClient
from quintoandar_airtable_api_client.consumers import AirtableConsumer
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
    BaseSparkContext,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.formatters import StringFormatter
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_airtable_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def extend_incremental_params(params: dict, execution_date: str) -> dict:
    """
    Function to parse and add incremental param in the current params.

    :param params: Dict with request params
    :type params: dict
    :param execution_date: Execution_date as string
    :type execution_date: str
    :return: Dict of extended params
    :rtype: dict
    """

    dt_started = datetime.strptime(execution_date, "%Y-%m-%d")
    dt_ended = (dt_started + timedelta(days=1)).strftime("%Y-%m-%d")
    filter_by_formula = f"""
        OR(
            AND(
                LAST_MODIFIED_TIME() >= '{dt_started}', 
                LAST_MODIFIED_TIME() < '{dt_ended}'
            ),
            AND(
                CREATED_TIME() >= '{dt_started}',
                CREATED_TIME() < '{dt_ended}'
            )
        )
    """
    params["filterByFormula"] = filter_by_formula

    return params


def normalize_record(record):
    """
    Normalizes the keys of a given dictionary by converting them to alphanumeric snake_case and handles duplicates.

    :param record: A dictionary containing the original keys that need to be normalized.
    :type record: dict
    :return: A new dictionary with the keys normalized to alphanumeric snake_case format, with duplicates handled.
    :rtype: dict
    """

    normalized_record = {}
    for key, value in record.items():
        normalized_key = StringFormatter.set_alphanumeric_snake_case(key)
        normalized_record[normalized_key] = value
    return normalized_record


def rename_duplicate_columns(dataframe):
    """
    Function to rename duplicate columns in a DataFrame by adding a suffix to ensure unique column names.

    :param dataframe: The DataFrame with potentially duplicate column names.
    :type dataframe: pyspark.sql.DataFrame
    :return: A list of column names with duplicates renamed to ensure uniqueness.
    :rtype: list[str]
    """

    columns_name = dataframe.columns
    duplicate_columns_index = [
        idx for idx, val in enumerate(columns_name) if val in columns_name[:idx]
    ]

    for idx in duplicate_columns_index:
        columns_name[idx] = columns_name[idx] + "_duplicate_" + str(idx)

    return columns_name


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("execution_date", help="execution date in str format %Y-%m-%d")
    parser.add_argument("table_name", help="Name of the table to store data into")
    parser.add_argument("partitions", help="Partition columns name")
    parser.add_argument("required_params", help="")
    parser.add_argument("optional_params", help="")

    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    partition_cols = ast.literal_eval(args.partitions)
    required_params = json.loads(args.required_params)
    optional_params = json.loads(args.optional_params)

    execution_date = args.execution_date

    base_id = required_params["base_id"]
    table_id = required_params["table_id"]

    extended_params = extend_incremental_params(optional_params, execution_date)
    path = f"{base_id}/{table_id}"

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                execution_date={execution_date} msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    # Initializing clients
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    api_token = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.AIRTABLE)
    )

    airtable_client = AirtableClient(api_token=api_token["auth_token"])
    airtable_consumer = AirtableConsumer(client=airtable_client, path=path)

    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()

    records = airtable_consumer.sync(params=extended_params)

    if records:

        logger.info(
            f"""
                    m=__main__, table_name={table_name}, base_id={base_id}, table_id={table_id},
                    params={optional_params} msg=Records found.
            """
        )

        # Create an RDD from the list of records
        rdd = BaseSparkContext.sc.parallelize(records)

        # Normalize each record in the RDD by transforming column names.
        rdd_normalized = rdd.map(
            lambda rec: {
                **normalize_record(rec["fields"]),
                **{key: rec[key] for key in rec if key != "fields"},
            }
        )

        # Aggregates the keys from a dictionary into a set to track all unique column names.
        all_column_names = rdd_normalized.aggregate(
            zeroValue=set(),
            seqOp=lambda accum, rec: accum.update(rec.keys()) or accum,
            combOp=lambda accum1, accum2: accum1.update(accum2) or accum1,
        )

        # Define the schema for the DataFrame based on the unique column names
        schema = StructType(
            [StructField(col, StringType(), True) for col in list(all_column_names)]
        )

        # Create a DataFrame from the normalized RDD and the defined schema
        df = spark_client.create_dataframe(rdd_normalized, schema)

        # Rename any duplicate columns in the DataFrame, if present
        new_columns_name = rename_duplicate_columns(df)
        df = df.toDF(*new_columns_name)

        # Process the DataFrame by adding year, month, and day columns based on the date
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(
                datetime.strptime(execution_date, "%Y-%m-%d")
            )
            .output()
        )

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
    else:
        logger.warning(
            f"""
                    m=__main__, table_name={table_name}, base_id={base_id}, table_id={table_id},
                    params={optional_params} msg=No records found.
            """
        )
