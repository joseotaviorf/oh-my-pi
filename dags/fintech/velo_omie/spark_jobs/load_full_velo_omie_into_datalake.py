import ast
import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_omie_api_client.clients.omie_client import OmieClient
from quintoandar_omie_api_client.consumers import CONSUMERS

from pyspark.sql.functions import col, when

JOB_NAME = "load_full_velo_omie_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def dict_flatner(dic: dict):
    final_result = {}
    for key, val in dic.items():
        if isinstance(val, dict):
            final_result = {**final_result, **val}
        else:
            final_result[key] = val
    return final_result


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument(
        "api_consumer_id", type=str, help="The consumer that will be used to load data"
    )
    parser.add_argument(
        "consumer_args",
        type=str,
        help="Dict in string with arguments for the consumer function",
    )

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    api_consumer_id = args.api_consumer_id
    consumer_args = args.consumer_args

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name}, api_consumer_id={api_consumer_id}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=APIEnum.VELO_OMIE_API
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

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    client = OmieClient(conn_config["app_key"], conn_config["app_secret"], attempts=0)
    consumer_instance = CONSUMERS[api_consumer_id](client)

    consumer_args = ast.literal_eval(consumer_args)

    json_list = consumer_instance.sync(**consumer_args)
    json_list = [dict_flatner(record) for record in json_list]

    df = spark_client.create_dataframe(json_list)

    complex_types = ["array", "map"]
    # Replace empty string for NULL on non-complex types
    for i in df.columns:
        if any(type_ not in dict(df.dtypes)[i] for type_ in complex_types):
            df = df.withColumn(i, when((col(i) == ""), None).otherwise(col(i)))

    if df:
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            database_location=database_location,
            max_records_per_file=100000,
        )
        spark_metastore_loader.update_metastore(
            df, database_name, table_name, format_options, database_location
        )
    else:
        logger.warning(
            f"""m=__main__, table_name={table_name},
            msg=No data returned from API database."""
        )
