import ast
import io
import json
import logging
import re
import zipfile
from argparse import ArgumentParser

import pandas as pd
import requests
from pyspark.sql.functions import current_date, lit
from pyspark.sql.functions import max as spark_max
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline import FullTableLoaderPipeline
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

IPTU_REGION = "iptu_sp"
# Matches workflow custom_schema in iptu_sp_declaration.yml (shared datalake_iptu_raw DB).
METASTORE_SOURCE = "iptu"
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

    add_validation_target_args(parser)
    args = parser.parse_args()

    return (
        args.env,
        args.datalake_bucket,
        args.source,
        args.execution_date,
        args.target_database_name,
        args.target_table_name,
    )


def get_most_recent_year(json_string):
    data_dict = json.loads(json_string)
    files_list = data_dict["d"].split("|")
    most_recent_file = sorted(files_list)[-1]
    year_regex = re.search(r"\d{4}", most_recent_file)
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
    with zipfile.ZipFile(io.BytesIO(content), "r") as zip_ref:
        zip_files = zip_ref.namelist()
        csv_files = [file for file in zip_files if file.endswith(format)]

        if len(csv_files) == 0:
            raise Exception("No CSV files found in the ZIP.")

        if len(csv_files) > 1:
            raise Exception(
                f"More than one CSV file found. Total CSV files: {len(csv_files)}. Processing only the first one."
            )

        with zip_ref.open(csv_files[0]) as f:
            df = pd.read_csv(f, encoding="ISO-8859-1", delimiter=";")
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


def get_last_ingested_year(
    database_name: str,
    table_name: str,
    *,
    validation_run: bool = False,
) -> int:
    """Return the latest ingested IPTU year for the given write target."""
    if validation_run:
        metastore = SparkMetastoreService(spark_client)
        try:
            if table_name not in metastore.get_table_names(database_name):
                logger.info(
                    f"m=get_last_ingested_year, database_name={database_name}, "
                    f"table_name={table_name}, "
                    "msg=Validation write target missing; treating as empty."
                )
                return 0
        except Exception:
            logger.info(
                f"m=get_last_ingested_year, database_name={database_name}, "
                f"table_name={table_name}, "
                "msg=Validation database unavailable; treating as empty."
            )
            return 0

    spark.catalog.setCurrentDatabase(database_name)
    year = (
        spark.table(table_name)
        .agg(spark_max("year").alias("year"))
        .collect()[0]["year"]
    )
    return int(year) if year is not None else 0


def load_dataframe_into_datalake(
    df,
    table_name,
    environment,
    source,
    datalake_bucket,
    target_database_name: str = None,
    target_table_name: str = None,
):
    db_info = DatalakeMetastoreService.get_db_info(
        environment, METASTORE_SOURCE, datalake_bucket
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=target_database_name,
            target_table=target_table_name,
        )
    )
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(write_database_name)

    if df.rdd.isEmpty():
        logger.info(f"m=__main__, msg={table_name}'s RDD is empty")

    FullTableLoaderPipeline(
        write_database_name,
        write_table_name,
        write_location,
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
        target_database_name,
        target_table_name,
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

    last_iptu_available_year = get_last_iptu_available(
        path=source_url + source_years_path, headers=source_headers, data=source_data
    )
    db_info = DatalakeMetastoreService.get_db_info(
        environment, METASTORE_SOURCE, datalake_bucket
    )
    write_database_name, write_table_name, _ = resolve_datalake_write_target(
        prod_database=db_info["db_raw_databricks"],
        prod_table=table_name,
        prod_location=db_info["db_raw_path"],
        bucket=datalake_bucket,
        target_database=target_database_name,
        target_table=target_table_name,
    )
    validation_run = is_validation_run(target_database_name, target_table_name)
    last_ingested_year = get_last_ingested_year(
        write_database_name,
        write_table_name,
        validation_run=validation_run,
    )

    if last_iptu_available_year <= last_ingested_year:
        logger.info(
            """
            msg= This year's IPTU has already been downloaded, we're leaving the spark job.
            """
        )

        return None

    dataframe = get_data(
        url=source_url + source_url_to_download,
        year=last_iptu_available_year,
        format=source_format,
    )

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
            target_database_name=target_database_name,
            target_table_name=target_table_name,
        )


if __name__ == "__main__":
    main()
