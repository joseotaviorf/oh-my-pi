import io
import re
import ast
import json
import logging
import zipfile
import requests

import pandas as pd
from argparse import ArgumentParser
from quintoandar_logger import QuintoAndarLogger
from pyspark.sql.functions import lit, current_date

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline import FullTableLoaderPipeline
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

IPTU_REGION = "iptu_sp"
JOB_NAME = f"load_{IPTU_REGION}_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient()

def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    return (
        args.env,
        args.datalake_bucket,
        args.source,
        args.execution_date,
    )

def get_most_recent_year(json_string):
    data_dict = json.loads(json_string)
    files_list = data_dict["d"].split('|')
    most_recent_file = sorted(files_list)[-1]
    year_regex = re.search(r'\d{4}', most_recent_file)
    return int(year_regex.group())

def get_last_iptu_available(path, headers, data):
    response = requests.post(path, headers=headers, data=data)
    return get_most_recent_year(response.text)

def standardize_column_names(name):
    standardized_name = name.lower().replace(" ", "_").replace("/", "_")
    return standardized_name

def get_zip_files_content(url, year, format):
    response = requests.get(url.format(year=year))
    response.raise_for_status()
    return response.content

def process_zip_file(content, year, format):
    with zipfile.ZipFile(io.BytesIO(content), 'r') as zip_ref:
        zip_files = zip_ref.namelist()
        csv_files = [file for file in zip_files if file.endswith(format)]

        if len(csv_files) == 0:
            raise Exception("No CSV files found in the ZIP.")

        if len(csv_files) > 1:
            raise Exception(f"More than one CSV file found. Total CSV files: {len(csv_files)}. Processing only the first one.")

        with zip_ref.open(csv_files[0]) as f:
            df = pd.read_csv(f, encoding='ISO-8859-1', delimiter=';')
            df = df.rename(columns=standardize_column_names)
            df = spark.createDataFrame(df.astype(str))
            df = df.replace("nan", None)
            df = df.withColumn("year", lit(year))
            df = df.withColumn("dt_load", lit(current_date()))
            logger.info(f"Processed file: {csv_files[0]}")
            return df

def get_data(url, year, format):
    zip_files = get_zip_files_content(url, year, format)
    return process_zip_file(zip_files, year, format)

def load_dataframe_into_datalake(
    df, table_name, environment, source, datalake_bucket
):
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    if df.rdd.isEmpty():
        logger.info(f"m=__main__, msg={table_name}'s RDD is empty")

    FullTableLoaderPipeline(
        database_name,
        table_name,
        database_location,
        LayerEnum.RAW,
        None,
        None,
    ).load_and_register(df, format_options)


def main():
    (
        environment,
        datalake_bucket,
        source,
        execution_date,
    ) = parse_arguments()

    logger.info(
        f"""
        m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source},
        execution_date={execution_date}
        msg=Starting Spark job...
        """
    )

    config_service = ConfigurationService(source)

    table_name = IPTU_REGION
    source_url = config_service.get_config("url")
    source_url_to_download = config_service.get_config("download_url")
    source_years_path = config_service.get_config("iptu_years_path")
    source_headers = ast.literal_eval(config_service.get_config("headers"))
    source_data = json.dumps(ast.literal_eval(config_service.get_config("data")))
    source_format = config_service.get_config("format")

    logger.info(
        f"""
        m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source}, execution_date={execution_date}
        msg=Configuration table, table_name={table_name}, source_format={source_format},
        """
    )

    last_iptu_available_year = get_last_iptu_available(path=source_url + source_years_path, headers=source_headers, data=source_data)
    last_ingested_year = spark.sql(f"SELECT MAX(year) AS year FROM datalake_iptu_raw.{table_name}").select("year").rdd.flatMap(lambda x: x).collect()[0]

    if last_iptu_available_year <= last_ingested_year:

        logger.info(
            f"""
            msg= This year's IPTU has already been downloaded, we're leaving the spark job.
            """
        )

        return None

    dataframe = get_data(url=source_url + source_url_to_download, year=last_iptu_available_year, format=source_format)

    if dataframe:
        logger.info(
            f"""
            m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source}, execution_date={execution_date}
            msg=Dataframe imported with success.
            """
        )

        load_dataframe_into_datalake(
            dataframe,
            table_name,
            environment,
            source,
            datalake_bucket,
        )

if __name__ == "__main__":
    main()
