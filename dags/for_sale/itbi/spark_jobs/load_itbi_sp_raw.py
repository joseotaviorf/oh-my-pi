import logging
import pandas as pd
import requests
import re

from argparse import ArgumentParser
from datetime import date
from functools import reduce

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

from pyspark.sql.functions import lit, expr, udf
from pyspark.sql.types import IntegerType, StringType


ITBI_REGION = "itbi_sp"
JOB_NAME = f"load_{ITBI_REGION}_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient()

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
    itbi_configs = config_service.get_config("tables")[ITBI_REGION]

    table_name = ITBI_REGION
    source_download_page_url = itbi_configs["source"]["site_download_page_url"]
    source_format = itbi_configs["source"]["format"]
    source_blacklist_urls = itbi_configs["source"]["blacklist_urls"]
    is_incremental = itbi_configs["is_incremental"]
    columns_rename_mapped = itbi_configs["columns_to_rename"]
    problematic_columns_rename_mapped = itbi_configs["problematic_columns_to_rename"]


    logger.info(
        f"""
        m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source}, execution_date={execution_date}
        msg=Configuration table, table_name={table_name}, source_format={source_format}, is_incremental={is_incremental}
        """
    )

    dataframe = get_data(
        source_download_page_url,
        source_format,
        source_blacklist_urls,
        columns_rename_mapped,
        problematic_columns_rename_mapped
    )

    if dataframe:
        logger.info(
            f"""
            m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source}, execution_date={execution_date}
            msg=Dataframe imported with sucess.
            """
        )

        load_dataframe_into_datalake(
            dataframe,
            table_name,
            is_incremental,
            environment,
            source,
            datalake_bucket,
        )

def get_data(
    source_download_page_url,
    source_format,
    source_blacklist_urls,
    columns_rename_mapped,
    problematic_columns_rename_mapped,
):
    udf_transform_month_to_portuguese_relative = udf(
        transform_month_to_portuguese_relative, StringType()
    )

    urls = scrap_files_url(source_download_page_url, source_format)
    urls = [url for url in urls if url not in source_blacklist_urls]

    dataframes = []

    for url in urls:

        logger.info(
            f"""
            msg= Downloading url={url}
        """
        )

        sheets = pd.read_excel(url, sheet_name=None)
        sheets = {k: sheets[k] for k in sheets if re.match("[a-zA-Z]+-[0-9]+", k)}

        list_of_sheets = [df.assign(name=n) for n, df in sheets.items()]

        treated_sheets = []

        for sheet in list_of_sheets:
          df = spark_client.conn.createDataFrame(sheet.astype(str))

          df = df.replace("nan", None)
          df = df.withColumnRenamed("name", "source_tab")
          df = df.withColumn("source_file", lit(url))
          df = df.withColumn("year", expr("substring(source_tab, 5, length(source_tab))"))
          df = df.withColumn("year", df.year.cast(IntegerType()))
          df = df.withColumn("month", expr("substring(source_tab, 0, 3)"))
          df = df.withColumn("month", udf_transform_month_to_portuguese_relative("month"))
          df = df.withColumn("month", df.month.cast(IntegerType()))
          df = df.withColumn("dt_load", lit(date.today()))

          if columns_rename_mapped:
              df = rename_columns(df, columns_rename_mapped, problematic_columns_rename_mapped)
              df = df.drop(*[col for col in df.columns if "Unnamed" in col])

          treated_sheets.append(df)

        full_year_dataframe = reduce(lambda df1, df2: df1.unionByName(df2, allowMissingColumns=True), treated_sheets)

        dataframes.append(full_year_dataframe)

    logger.info(
        f"""
        msg= Getting out of the download loop. {len(dataframes)} worksheets was downloaded.
    """
    )

    dataframe = reduce(lambda df1, df2: df1.unionByName(df2, allowMissingColumns=True), dataframes)

    return dataframe

def extract_urls(request_response, source_format):
    return re.findall(r'<a\s+(?:[^>]*?\s+)?href="([^"]*itbi.*?\{source_format})"'.format(source_format = source_format), request_response.text, re.IGNORECASE)

def extract_google_drive_urls(request_response):
    drive_ids = re.findall(r'docs\.google\.com/spreadsheets/d/([a-zA-Z0-9_-]+)', request_response.text)
    return ['https://drive.google.com/uc?export=download&id={}'.format(drive_id) for drive_id in drive_ids]

def scrap_files_url(source_download_page_url, source_format):
    u = requests.get(source_download_page_url)
    xslx_urls = extract_urls(u, source_format)
    drive_urls = extract_google_drive_urls(u)
    return xslx_urls + drive_urls

def rename_columns(dataframe, columns_rename_mapped, problematic_columns_rename_mapped):
  columns_rename_mapped = dict(columns_rename_mapped)
  problematic_columns = set(dataframe.columns) & set(problematic_columns_rename_mapped)

  if problematic_columns:
    for column in problematic_columns:
      columns_rename_mapped = {**columns_rename_mapped, **problematic_columns_rename_mapped[column]}

  for old_name, new_name in columns_rename_mapped.items():
      dataframe = dataframe.withColumnRenamed(old_name, new_name)

  return dataframe

def transform_month_to_portuguese_relative(month, reverse=True):

    months = {
        "1": "JAN",
        "2": "FEV",
        "3": "MAR",
        "4": "ABR",
        "5": "MAI",
        "6": "JUN",
        "7": "JUL",
        "8": "AGO",
        "9": "SET",
        "10": "OUT",
        "11": "NOV",
        "12": "DEZ",
    }

    if reverse:
        months = dict(zip(months.values(), months.keys()))

    return months[str(month)]

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
