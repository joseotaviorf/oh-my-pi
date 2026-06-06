import json
import logging
from argparse import ArgumentParser

import requests
from pyspark.sql.functions import coalesce, col, lit
from pyspark.sql.types import StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_quires_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient()


def api_request(api_url, table_name, start_date, end_date, cursor=None):
    """
    Makes a request to the Quires API

    Args:
        api_url: Base API URL
        table_name: API endpoint
        start_date: Start date in YYYY-MM-DD format
        end_date: End date in YYYY-MM-DD format
        cursor: Pagination cursor (optional)

    Returns:
        API response (dict format)
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    headers = {
        "X-API-Key": json.loads(
            dbutils.secrets.get(scope="quintoandar", key=APIEnum.QUIRES)
        )["token"],
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    url = f"{api_url}/{table_name.lstrip('/')}"

    params = {"start": start_date, "end": end_date}

    if cursor:
        params["cursor"] = cursor

    try:
        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()  # Raise exception for HTTP error status
        return response.json()
    except requests.exceptions.RequestException as e:
        logger.error(f"API request error: {e}")
        raise


def get_all_data(
    api_url,
    table_name,
    start_date,
    end_date,
    target_database_name: str = None,
    target_table_name: str = None,
):
    """
    Returns all data from the period by performing cursor-based pagination

    Args:
        api_url: Base API URL
        table_name: API endpoint (access, activations, properties)
        start_date: Start date in YYYY-MM-DD format
        end_date: End date in YYYY-MM-DD format

    Returns:
        List with data from all pages
    """
    all_data = []
    cursor = None

    while True:
        response = api_request(api_url, table_name, start_date, end_date, cursor)

        page_data = response.get("data", [])
        all_data.extend(page_data)

        cursor = response.get("cursor")
        if cursor is None:
            break

    return all_data


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("table_name")

    add_validation_target_args(parser)
    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    table_name = args.table_name

    config_service = ConfigurationService(source)
    api_url = config_service.get_config("api_url")
    raw_partition_cols = config_service.get_config("raw_partition_cols")

    schema_config = (
        config_service.get_config("table_schemas")[table_name]
        if table_name in config_service.get_config("table_schemas")
        else None
    )
    schema = (
        StructType.fromJson(json.loads(schema_config.get("schema")))
        if schema_config
        else None
    )

    logger.info(
        f"m={JOB_NAME}, environment={env}, datalake_bucket={datalake_bucket}, table_name={table_name}, "
        f"load_start_date={load_start_date}, load_end_date={load_end_date}, raw_partition_cols={raw_partition_cols}, table_schema={schema}, "
        f"msg=Starting spark job..."
    )

    client_response = get_all_data(api_url, table_name, load_start_date, load_end_date)

    if client_response:
        spark_client = SparkClient()
        if schema:
            df = spark_client.create_dataframe(client_response, schema=schema)
        else:
            df = spark_client.create_dataframe(client_response)

        if table_name == "properties":
            df = df.withColumn("load_date", lit(load_end_date))
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column("load_date")
                .output()
            )
        elif table_name == "urls":
            # New records in URLs don't have an updatedAt, so we use the createdAt
            df = df.withColumn(
                "updatedAt", coalesce(col("updatedAt"), col("createdAt"))
            )
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column("updatedAt")
                .output()
            )
        else:
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column("createdAt")
                .output()
            )

        datalake_info = DatalakeMetastoreService.get_db_info(
            env, source, datalake_bucket
        )
        spark_metastore_service = SparkMetastoreService(spark_client)
        database_name = datalake_info["db_raw_databricks"]
        database_location = datalake_info["db_raw_path"]
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
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        # loaders
        s3_loader = S3Loader()
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader.load_df(
            df=df,
            s3_path=f"{write_location}{write_table_name}",
            format_options=format_options,
            partitions=raw_partition_cols,
        )
        spark_metastore_loader.update_metastore(
            df,
            write_database_name,
            write_table_name,
            format_options,
            write_location,
            raw_partition_cols,
            force_recreate=False,
        )
        spark_metastore_service.create_new_partitions_from_df(
            database_name=write_database_name,
            table_name=write_table_name,
            df=df,
            partition_cols=raw_partition_cols,
        )

        full_write_table_name = f"{write_database_name}.{write_table_name}"
        table_privileges = TablePrivileges.from_environment_default(
            full_write_table_name
        )
        if table_privileges and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
            table_privileges.apply()

        spark_metastore_service.refresh_table(write_database_name, write_table_name)

    else:
        logger.warning(
            f"m=__main__, load_start_date={load_start_date}, load_end_date={load_end_date}, "
            f"table_name={table_name}, msg=No data returned from API."
        )
