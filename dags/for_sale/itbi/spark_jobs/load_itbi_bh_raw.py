import re
import ast
import logging
import requests
import unidecode

import pandas as pd
from io import StringIO
from datetime import date, datetime
from functools import reduce
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from pyspark.sql.functions import lit, to_date, to_timestamp, coalesce, year, month

from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

ITBI_REGION = "itbi_bh"
JOB_NAME = f"load_{ITBI_REGION}_raw"


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient()


def main():
    (environment, datalake_bucket, source, execution_date) = parse_arguments()

    logger.info(
        f"""
        m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source},
         execution_date={execution_date}
         msg=Starting Spark job...
        """
    )

    config_service = ConfigurationService(source)
    itbi_configs = config_service.get_config("tables")[ITBI_REGION]

    table_name = ITBI_REGION
    source_download_page_url = itbi_configs["source"]["site_download_page_url"]
    source_headers = ast.literal_eval(itbi_configs["source"]["headers"])
    source_format = itbi_configs["source"]["format"]
    source_blacklist_urls = itbi_configs["source"]["blacklist_urls"]
    is_incremental = itbi_configs["is_incremental"]
    columns_rename_mapped = itbi_configs["columns_to_rename"].items()

    logger.info(
        f"""
        m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source}, execution_date={execution_date}
        msg=Configuration table, table_name={table_name}, source_format={source_format}, is_incremental={is_incremental}
        """
    )

    dataframe = get_data(
        source_download_page_url,
        source_headers,
        source_format,
        source_blacklist_urls,
        columns_rename_mapped,
    )

    if dataframe:
        logger.info(
            f"""
            m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source}, execution_date={execution_date}
            msg=Dataframe imported with sucess.
            """
        )

        load_dataframe_into_datalake(
            dataframe, table_name, is_incremental, environment, source, datalake_bucket
        )


def get_data(
    source_download_page_url,
    source_headers,
    source_format,
    source_blacklist_urls,
    columns_rename_mapped,
):
    urls = scrap_files_url(source_download_page_url, source_headers, source_format)
    urls = [url for url in urls if url not in source_blacklist_urls]

    dataframes = []

    for url in urls:

        logger.info(
            f"""
            msg= Downloading url={url}
        """
        )

        response = requests.get(url, headers=source_headers)

        response.encoding = 'utf-8'  # Set encoding to handle special characters
        csv_content = StringIO(response.text)

        df = pd.read_csv(csv_content, sep=';', thousands='.', decimal=',', skip_blank_lines=True)
        df.columns = df.columns.str.strip()  # Strip whitespace from column names
        df = df.applymap(lambda x: x.strip() if isinstance(x, str) else x)  # Strip whitespace from data cells

        df = spark_client.conn.createDataFrame(df.astype(str))

        df = df.replace("nan", None)
        df = df.withColumn("source_file", lit(url))
        df = df.withColumn("dt_load", lit(date.today()))

        if columns_rename_mapped:
            df = rename_columns(df, columns_rename_mapped)

        df = df.withColumn(
            "data_inclusao_transacao",
            coalesce(
                to_timestamp("data_inclusao_transacao", "dd/MM/yyyy HH:mm"),
                to_timestamp("data_inclusao_transacao", "yyyy/MM/dd HH:mm:ss"),
                to_date("data_inclusao_transacao", "dd/MM/yyyy"),
            ),
        )
        df = df.withColumn("month", month("data_inclusao_transacao"))
        df = df.withColumn("year", year("data_inclusao_transacao"))
        df = df.filter("year IS NOT NULL AND month IS NOT NULL")

        dataframes.append(df)

    logger.info(
        f"""
        msg= Getting out of the download loop. {len(dataframes)} worksheets was downloaded.
    """
    )

    dataframe = reduce(
        lambda df1, df2: df1.unionByName(df2, allowMissingColumns=True), dataframes
    )

    return dataframe


def scrap_files_url(source_download_page_url, source_headers, source_format):
    u = requests.get(source_download_page_url, headers=source_headers)
    urls = re.findall(
        r'<a\s+(?:[^>]*?\s+)?href="([^"]*itbi.*?\{source_format})"'.format(
            source_format=source_format
        ),
        u.text,
        re.IGNORECASE,
    )
    return urls


def rename_columns(dataframe, columns_rename_mapped):

    for old_name, new_name in columns_rename_mapped:
        dataframe = dataframe.withColumnRenamed(old_name, new_name)

    return dataframe


def load_dataframe_into_datalake(
    df, table_name, is_incremental, environment, source, datalake_bucket
):
    """Loads the dataframes into S3, either incrementally or fully, depending on the config."""

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    partition_cols = ["year", "month"]

    if df.rdd.isEmpty():
        logger.info(f"m=__main__, msg={table_name}'s RDD is empty")

    if is_incremental:
        IncrementalTableLoaderPipeline(
            database_name,
            table_name,
            database_location,
            LayerEnum.RAW,
            None,
            partition_cols,
        ).load_and_register(df, format_options)
    else:
        FullTableLoaderPipeline(
            database_name,
            table_name,
            database_location,
            LayerEnum.RAW,
            None,
            partition_cols,
        ).load_and_register(df, format_options)


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


if __name__ == "__main__":
    main()
