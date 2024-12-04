import json
import logging
from datetime import datetime, timedelta
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.base.spark.spark_dataframe_service import SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline.full_table_loader_pipeline import FullTableLoaderPipeline
from bietlejuice.pipeline.incremental_table_loader_pipeline import IncrementalTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_asaas_api_client.clients.asaas_api_client_python_client import AsaasApiClientPythonClient
from quintoandar_asaas_api_client.consumers import CONSUMERS
from quintoandar_asaas_api_client.constants.endpoint_enum import EndpointEnum

from pyspark.sql.types import StructType, StructField, StringType
JOB_NAME = "load_velo_asaas_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

DEFAULT_PARTITION_COLUMNS = ['year','month','day']

TABLES_ENDPOINT_ENUM = {
    "payments":EndpointEnum.PAYMENTS_PAGED.value,
    "customers":EndpointEnum.CUSTOMERS_PAGED.value,
}

def dict_flatner(dic: dict):
    final_result = {}
    for key, val in dic.items():
        if isinstance(val, dict):
            for key2, val2 in val.items():
                final_result = {**final_result, f'{key}_{key2}': val2}
        else:
            final_result[key] = str(val)
    return final_result

def create_schema(json_list: list):
    cols = set()
    for row in json_list:
        [cols.add(key) for key in row.keys()]

    schema = []
    for col in cols:
        schema.append(StructField(col, StringType(), True))
    return StructType(schema)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("execution_date")
    parser.add_argument("load_mode")


    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_mode = args.load_mode
    table_name = args.table_name
    execution_date = args.execution_date
    execution_datetime = datetime.strptime(execution_date, "%Y-%m-%d")
    tomorrow_date = execution_datetime + timedelta(days=1)
    tomorrow_date = tomorrow_date.strftime("%Y-%m-%d")
    api_consumer_id = "Parallel"
    consumer_args = {}

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=APIEnum.VELO_ASAAS
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)

    # create database if it doesn't exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    client = AsaasApiClientPythonClient(conn_config["api_token"])
    consumer_instance = CONSUMERS[api_consumer_id](TABLES_ENDPOINT_ENUM[table_name], client)

    json_list = consumer_instance.sync(**consumer_args)

    json_list = consumer_instance.sync(**consumer_args)
    json_list = [dict_flatner(record) for record in json_list]

    df = spark_client.create_dataframe(json_list, create_schema(json_list))
    if df:
        if load_mode == 'incremental':
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(execution_datetime)
                .output()
            )
            IncrementalTableLoaderPipeline(
                database_name=database_name,
                table_name=table_name,
                database_location=database_location,
                layer=LayerEnum.RAW,
                query=None,
                partitions=DEFAULT_PARTITION_COLUMNS,
            ).load_and_register(df, format_options)
        else:
            FullTableLoaderPipeline(
                database_name=database_name,
                table_name=table_name,
                database_location=database_location,
                layer=LayerEnum.RAW,
                query=None
            ).load_and_register(df, format_options)

    else:
        logger.warning(
            f"""m=__main__, table_name={table_name},
            msg=No data returned from API."""
        )
