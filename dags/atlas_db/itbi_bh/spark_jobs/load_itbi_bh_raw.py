import ast
import logging
import pandas as pd
import re
import requests

from argparse import ArgumentParser
from datetime import date
from functools import reduce
from io import StringIO
from typing import Dict, List, Optional

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader

from pyspark.sql.functions import lit, to_date, to_timestamp, coalesce, year, month
from pyspark.sql import DataFrame

from quintoandar_logger import QuintoAndarLogger


SOURCE = "itbi_bh"
JOB_NAME = f"load_{SOURCE}_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient()


def main():
  (
      environment,
      datalake_bucket,
      schema,
      raw_table_name,
      partition_cols,
      execution_date,
  ) = parse_arguments()

  logger.info(
      f"""
      m=main, environment={environment}, datalake_bucket={datalake_bucket}, schema={schema},
        execution_date={execution_date}
        msg=Starting Spark job...
      """
  )

  config_service = ConfigurationService(SOURCE)

  source_download_page_url = config_service.get_config("site_download_page_url")
  source_headers = ast.literal_eval(config_service.get_config("headers"))
  source_format = config_service.get_config("format")
  source_blocklist_urls = config_service.get_config("blacklist_urls")
  columns_rename_mapped = config_service.get_config("columns_to_rename")

  logger.info(
      f"""
      m=main, environment={environment}, datalake_bucket={datalake_bucket}, schema={schema}, execution_date={execution_date}
      msg=Configuration table, table_name={raw_table_name}, source_format={source_format}
      """
  )

  df_itbi_bh_source = get_data(
      columns_rename_mapped=columns_rename_mapped,
      source_blocklist_urls=source_blocklist_urls,
      source_download_page_url=source_download_page_url,
      source_format=source_format,
      source_headers=source_headers,
  )

  if df_itbi_bh_source:
    logger.info(
        f"""
        m=main, environment={environment}, datalake_bucket={datalake_bucket}, schema={schema}, execution_date={execution_date}
        msg=Dataframe imported with sucess.
        """
    )

    load_dataframe_into_datalake(
        df=df_itbi_bh_source,
        environment=environment,
        schema=schema,
        datalake_bucket=datalake_bucket,
        raw_table_name=raw_table_name,
        partition_cols=partition_cols,
    )
  else:
    raise Exception(f"m=Failed to ingest dataframe")


def get_data(
  columns_rename_mapped: Dict[str, str],
  source_blocklist_urls: List[str],
  source_download_page_url: str,
  source_format: str,
  source_headers: Dict[str, str],
):
  """
  Downloads the files from the source and returns a DataFrame.

  Args:
    columns_rename_mapped (Dict[str, str]): Dictionary mapping old column names to new ones.
    source_blocklist_urls (List[str]): List of URLs to ignore.
    source_download_page_url (str): The URL of the download page.
    source_format (str): The format of the files to extract.
    source_headers (Dict[str, str]): The headers to use in the request.

  Returns:
    DataFrame: The DataFrame containing the data from the source.
  """
  urls = scrap_files_url(
    source_blocklist_urls = source_blocklist_urls,
    source_download_page_url=source_download_page_url,
    source_format=source_format,
    source_headers=source_headers,
  )

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
      df = rename_columns(columns_rename_mapped=columns_rename_mapped, dataframe=df)

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


def extract_urls(
  blocklist_urls: List[str],
  request_response: str,
  source_download_page_url: str,
  source_format: str,
) -> Optional[List[str]]:
  """
  Extract URLS from the response content that match the specified format.

  Args:
    blocklist_urls (List[str]): List of URLs to ignore.
    request_response (str): The response content.
    source_download_page_url (str): The URL of the download page.
    source_format (str): The format of the files to extract.

  Returns:
    Optional[List[str]]: A list of URLs that match the specified format.
  """
  try:
    pattern = r'<a\s+(?:[^>]*?\s+)?href="([^"]*itbi.*?\{source_format})"'.format(source_format=source_format)
    urls = re.findall(pattern, request_response.text, re.IGNORECASE)
    filtered_urls = list(set([url for url in urls if url not in blocklist_urls]))
    logger.info(f"m=extract_urls, msg=Extracted {len(filtered_urls)} URLs from {source_download_page_url}")
    return filtered_urls
  except Exception as e:
    logger.error(f"m=extract_urls, msg=Error extracting URLs: {e}")
    return None


def scrap_files_url(
  source_blocklist_urls: List[str],
  source_download_page_url: str,
  source_format: str,
  source_headers: Dict[str, str],
) -> Optional[List[str]]:
  """
  Scrapes file URLs from the provided download page, filtering blocklist URLs.

  Args:
    source_blocklist_urls (List[str]): List of URLs to ignore.
    source_download_page_url (str): The URL of the download page.
    source_format (str): The format of the files to extract.
    source_headers (dict): The headers to use in the request.

  Returns:
    Optional[List[str]]: A list of URLs that match the specified format.
  """
  try:
    response = requests.get(source_download_page_url, headers=source_headers)
    response.raise_for_status()

    urls = extract_urls(
      blocklist_urls=source_blocklist_urls,
      request_response=response,
      source_download_page_url=source_download_page_url,
      source_format=source_format,
    )
    return urls
  except requests.RequestException as e:
    logger.error(f"m=scrap_files_url, msg=Failed to retrieve page content: {e}")
    return None
  except Exception as e:
    logger.error(f"m=scrap_files_urls, msg=An error ocurred: {e}")
    return None


def rename_columns(
  columns_rename_mapped: Dict[str, str],
  dataframe: DataFrame,
  ) -> DataFrame:
  """
  Renames columns in the DataFrame based on provided mappings, handling problematic columns.

  Args:
      columns_rename_mapped (dict): Dictionary mapping old column names to new ones.
      dataframe (DataFrame): The Spark DataFrame to process.
  Returns:
      DataFrame: The DataFrame with renamed columns.
  """
  columns_rename_mapped = dict(columns_rename_mapped)

  for old_name, new_name in columns_rename_mapped.items():
      dataframe = dataframe.withColumnRenamed(old_name, new_name)

  return dataframe

def load_dataframe_into_datalake(
  datalake_bucket: str,
  df: DataFrame,
  environment: str,
  partition_cols: List[str],
  raw_table_name: str,
  schema: str,
):
  """
  Loads a DataFrame into the Data Lake.

  Args:
      datalake_bucket (str): The name of the datalake bucket.
      df (DataFrame): The DataFrame to be loaded.
      environment (str): The environment to load the data into.
      partition_cols (list): List of partition columns.
      raw_table_name (str): The name of the raw table.
      schema (str): The source of the data.

  Returns:
      None: None
  """

  db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
  database_name = db_info["db_raw_databricks"]
  database_location = db_info["db_raw_path"]
  format_options = SparkTableStorageFormat.DEFAULT_RAW

  s3_loader = S3Loader()
  spark_metastore_service = SparkMetastoreService(spark_client)
  spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

  logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
  spark_metastore_service.create_database(database_name)

  if df.rdd.isEmpty():
      logger.info(f"m=__main__, msg={raw_table_name}'s RDD is empty")

  s3_loader.load_df(
      df=df,
      s3_path=f"{database_location}/{raw_table_name}",
      format_options=format_options,
      partitions=partition_cols,
      compression="gzip"
  )

  spark_metastore_loader.update_metastore(
      df=df,
      database_name=database_name,
      table_name=raw_table_name,
      format_options=format_options,
      database_location=database_location,
      partitions=partition_cols,
      force_recreate=True,
  )

  spark_metastore_service.create_new_partitions_from_df(
      df=df,
      database_name=database_name,
      table_name=raw_table_name,
      partition_cols=partition_cols,
  )


def parse_arguments():
  parser = ArgumentParser(description=JOB_NAME)
  parser.add_argument("environment", help="Forno/Prod values")
  parser.add_argument("datalake_bucket", help="Bucket value in forno/prod")
  parser.add_argument("schema", help="Custom Schema to save table"),
  parser.add_argument("table_name", help="Name of the table to store data into")
  parser.add_argument("partitions", help="Partition columns name")
  parser.add_argument("execution_date", help="DAG execution_date")

  args = parser.parse_args()

  environment: str = args.environment
  datalake_bucket: str = args.datalake_bucket
  schema: str = args.schema
  raw_table_name: str = args.table_name
  partition_cols: List[str] = ast.literal_eval(args.partitions)
  execution_date: str = args.execution_date

  return (
        environment,
        datalake_bucket,
        schema,
        raw_table_name,
        partition_cols,
        execution_date,
  )

if __name__ == "__main__":
    main()
