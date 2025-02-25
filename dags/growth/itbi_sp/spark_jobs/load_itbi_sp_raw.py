import ast
import logging
import pandas as pd
import re
import requests
import time

from argparse import ArgumentParser
from datetime import date, datetime
from functools import reduce
from typing import Dict, List, Optional
from urllib.parse import urljoin

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat, SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader

import pyspark.sql.functions as F
from pyspark.sql import DataFrame
from pyspark.sql.types import IntegerType, StringType

from quintoandar_logger import QuintoAndarLogger


SOURCE = "itbi_sp"
JOB_NAME = f"load_{SOURCE}_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient()


def extract_urls(
  base_url:str,
  blocklist_urls:List[str],
  request_response:str,
  source_download_page_url:str,
  source_format:str,
  year_interval:List[str],
  ) -> Optional[List[str]]:
  """
  Extract URLs from the response content that match the specified format.

  Args:
      base_url (str): The base URL for joining relative paths.
      blocklist_urls (List[str]): List of forbidden URLs to be removed.
      request_response (str): Response text from the request.
      source_download_page_url (str): URL of the page to scrape for file links.
      source_format (str): The file format to search for (e.g., 'xlsx').
      year_interval (List[int]): List of years to extract from the URL.

  Returns:
      Optional[List[str]]: List of full URLs matching the format.
  """
  try:
    pattern = r'<a\s+(?:[^>]*?\s+)?href="([^"]*itbi.*?[\.|\-]{source_format})"'.format(source_format=source_format)
    year_pattern = re.compile(r'(\d{4})')

    urls = re.findall(pattern, request_response.text, re.IGNORECASE)
    full_urls = [urljoin(base_url, url) if url.startswith('/') else url for url in urls]

    filtered_urls = []
    for url in full_urls:
      match = year_pattern.search(url)
      if match:
        year = match.group(1)
        if year in year_interval and url not in blocklist_urls:
          filtered_urls.append(url)
      else:
        filtered_urls.append(url)
    logger.info(f"m=extract_urls, msg=Extracted {len(filtered_urls)} URLs for {source_download_page_url}.")
    return filtered_urls
  except Exception as e:
    logger.error(f"m=extract_urls, msg=Error extracting URLs: {e}")
    return None


def scrap_files_url(
  base_url:str,
  blocklist_urls:List[str],
  source_download_page_url:str,
  source_format:str,
  year_interval:List[str],
  ) -> Optional[List[str]]:
  """
  Scrapes file URLs from the provided download page, filtering blacklisted URLs.

  Args:
    base_url (str): Base URL for relative paths.
    blocklist_urls (List[str]): List of URLs to be removed.
    source_download_page_url (str): URL of the page to scrape for file links.
    source_format (str): Format of files to extract (e.g., 'xlsx').
    year_interval (List[int]): List of years to extract from the URL.

  Returns:
      Optional[List[str]]: List of valid URLs excluding blacklisted ones.
  """
  try:
    response = requests.get(source_download_page_url)
    response.raise_for_status()

    urls = extract_urls(
      base_url=base_url,
      blocklist_urls=blocklist_urls,
      request_response=response,
      source_download_page_url=source_download_page_url,
      source_format=source_format,
      year_interval=year_interval,
    )

    logger.info(f"m=scrap_files_url, msg=Scraped {len(urls)} valid URLs.")
    return urls
  except requests.RequestException as e:
    logger.error(f"m=scrap_files_url, msg=Failed to retrieve page content: {e}")
    return None
  except Exception as e:
    logger.error(f"m=scrap_files_url, msg=An error occurred: {e}")
    return None


def rename_columns(
  columns_rename_mapped:Dict[str,str],
  dataframe:DataFrame,
  problematic_columns_rename_mapped:Dict[str, Dict[str, str]],
  sheet_name:str,
  ) -> DataFrame:
  """
  Renames columns in the DataFrame based on provided mappings, handling problematic columns.

  Args:
      columns_rename_mapped (dict): Dictionary mapping old column names to new ones.
      dataframe (DataFrame): The Spark DataFrame to process.
      problematic_columns_rename_mapped (dict): Special mappings for problematic columns.
      sheet_name (str): The name of the sheet to process.

  Returns:
      DataFrame: The DataFrame with renamed columns.
  """
  columns_rename_mapped = dict(columns_rename_mapped)
  problematic_columns = set(dataframe.columns) & set(problematic_columns_rename_mapped)

  if problematic_columns:
    for column in problematic_columns:
      columns_rename_mapped = {**columns_rename_mapped, **problematic_columns_rename_mapped[column]}

  for old_name, new_name in columns_rename_mapped.items():
      dataframe = dataframe.withColumnRenamed(old_name, new_name)

  logger.info(f"m=rename_columns, msg=for {sheet_name} columns renamed.")
  return dataframe


def extract_sheets(
  url: str,
) -> Dict[str, pd.DataFrame]:
  """
  Extracts sheets from an Excel file at the provided URL.
  Args:
    url (str): The URL of the Excel file.
  Returns:
    Dict[str, DataFrame]: A dictionary of sheet names and their corresponding Spark DataFrames.
  """

  max_retries = 3
  retry_delay = 5

  for i in range(max_retries):
    try:
      response = requests.get(url)
      response.raise_for_status()
      sheets = pd.read_excel(response.content, sheet_name=None)
      break
    except requests.exceptions.RequestException as e:
      logger.error(f"Error: {e}")
      logger.error(f"Retrying in {retry_delay} seconds...")
      time.sleep(retry_delay)
  else:
      logger.info("Max retries exceeded. Unable to fetch data.")

  return sheets


def process_url(
  columns_rename_mapped: Dict[str,str],
  problematic_columns_rename_mapped: Dict[str, Dict[str, str]],
  url: str,
) -> List[DataFrame]:
  """
  Downloads and processes data from a single URL into a list of Spark DataFrames.

  Args:
      columns_rename_mapped (dict): Mapping of column renaming.
      problematic_columns_rename_mapped (dict): Special mapping for problematic columns.
      url (str): The URL to download data from.

  Returns:
      list: A list of processed Spark DataFrames.
  """

  logger.info(f"m=process_url, msg=Processing data from URL: {url}")

  sheets = extract_sheets(url)

  try:
    sheet_name_pattern = re.compile(r"[a-zA-Z]+-[0-9]+")
    sheets = {k: sheets[k] for k in sheets if sheet_name_pattern.match(k)}
  except Exception as e:
    logger.error(f"m=process_url, msg=Error processing URL {url}: {e}")
    return []

  list_of_sheets = [df.assign(name=n) for n, df in sheets.items()]
  treated_sheets: List[DataFrame] = []

  month_map = {
    "JAN": "1", "FEV": "2", "MAR": "3", "ABR": "4",
    "MAI": "5", "JUN": "6", "JUL": "7", "AGO": "8",
    "SET": "9", "OUT": "10", "NOV": "11", "DEZ": "12"
  }
  month_expr = F.create_map(*sum([[F.lit(k), F.lit(v)] for k, v in month_map.items()], []))

  for sheet in list_of_sheets:
    df = spark_client.conn.createDataFrame(sheet.astype(str))
    sheet_name = [row["name"] for row in df.select("name").distinct().collect()][0]
    logger.info(f"m=process_url, msg=Converted sheet {sheet_name} from URL {url} to Spark DataFrame with {df.count()} rows and {len(df.columns)-1} columns.")

    df = df.replace("nan", None) \
      .withColumnRenamed("name", "source_tab") \
      .withColumn("source_file", F.lit(url)) \
      .withColumn("dt_load", F.lit(date.today())) \
      .withColumn("year", F.expr("substring(source_tab, 5, length(source_tab))").cast(IntegerType())) \
      .withColumn("month", month_expr[F.expr("substring(source_tab, 0, 3)")].cast(IntegerType()))

    logger.info(f"m=process_url, msg=Added new columns for {sheet_name} from URL {url}.")

    if columns_rename_mapped:
        df = rename_columns(
          columns_rename_mapped=columns_rename_mapped,
          dataframe=df,
          problematic_columns_rename_mapped=problematic_columns_rename_mapped,
          sheet_name=sheet_name,
        )
        df = df.drop(*[col for col in df.columns if "Unnamed" in col])

    treated_sheets.append(df)

  if not treated_sheets:
    logger.warning(f"m=process_url, msg=No valid sheets processed from URL: {url}")

  return treated_sheets


def get_data(
  base_url: str,
  blocklist_urls: List[str],
  columns_rename_mapped: Dict[str, str],
  problematic_columns_rename_mapped: Dict[str, Dict[str, str]],
  source_download_page_url: str,
  source_format: str,
  year_interval: List[str],
) -> DataFrame:
  """
  Downloads and processes data from a specified source page and format.

  Args:
      base_url (str): Base URL for constructing absolute links.
      blocklist_urls (list): List of URLs to be ignored.
      columns_rename_mapped (dict): Mapping for renaming columns.
      problematic_columns_rename_mapped (dict): Mapping for problematic column renaming.
      source_download_page_url (str): URL of the page to download data from.
      source_format (str): Format of the files to be downloaded.
      year_interval (list): List of years to be downloaded.

  Returns:
      DataFrame: A combined DataFrame of all processed data.
  """

  urls = scrap_files_url(
    base_url=base_url,
    blocklist_urls=blocklist_urls,
    source_download_page_url=source_download_page_url,
    source_format=source_format,
    year_interval=year_interval
  )

  dataframes = []

  for url in urls:

    treated_sheets = process_url(
      url=url,
      columns_rename_mapped=columns_rename_mapped,
      problematic_columns_rename_mapped=problematic_columns_rename_mapped)

    full_year_dataframe = reduce(lambda df1, df2: df1.unionByName(df2, allowMissingColumns=True), treated_sheets)

    dataframes.append(full_year_dataframe)

  logger.info(
      f"""
      msg= Getting out of the download loop. {len(dataframes)} worksheets was downloaded.
      """
  )

  dataframe = reduce(lambda df1, df2: df1.unionByName(df2, allowMissingColumns=True), dataframes)
  logger.info(f"m=get_data, msg=Downloaded {len(dataframes)} sheets from {source_download_page_url} and merged them into a single dataframe.")

  return dataframe


def load_dataframe_into_datalake(
  datalake_bucket:str,
  df: DataFrame,
  environment:str,
  partition_cols:List[str],
  raw_table_name:str,
  schema:str,
  ) -> None:
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

  spark_client = SparkClient()

  db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
  database_name = db_info["db_raw_databricks"]
  database_location = db_info["db_raw_path"]
  format_options = SparkTableStorageFormat.DEFAULT_RAW

  s3_loader = S3Loader()
  spark_metastore_service = SparkMetastoreService(spark_client)
  spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

  spark_metastore_service.create_database(database_name)

  s3_loader.load_df(
    df=df,
    s3_path=f"{database_location}{raw_table_name}",
    format_options=format_options,
    partitions=partition_cols,
    compression="gzip",
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

  base_url = config_service.get_config("base_url")
  site_download_page_url = config_service.get_config("site_download_page_url")
  source_download_page_url = f"{base_url}{site_download_page_url}"
  source_format = config_service.get_config("source_format")
  blocklist_urls = config_service.get_config("blocklist_urls")
  columns_rename_mapped = config_service.get_config("columns_to_rename")
  problematic_columns_rename_mapped = config_service.get_config("problematic_columns_to_rename")
  diff_year = int(config_service.get_config("diff_year"))
  dt_execution_date = datetime.strptime(execution_date, "%Y-%m-%d")
  year_interval = [str(year) for year in range(dt_execution_date.year - diff_year, dt_execution_date.year + 1)]


  logger.info(
      f"""
      m=main, environment={environment}, datalake_bucket={datalake_bucket}, schema={schema}, execution_date={execution_date}
      msg=Configuration table, table_name={raw_table_name}, source_format={source_format}
      """
  )

  df_itbi_sp_source = get_data(
    base_url=base_url,
    blocklist_urls=blocklist_urls,
    columns_rename_mapped=columns_rename_mapped,
    problematic_columns_rename_mapped=problematic_columns_rename_mapped,
    source_download_page_url=source_download_page_url,
    source_format=source_format,
    year_interval=year_interval,
    )

  if df_itbi_sp_source:
    logger.info(
        f"""
        m=main, environment={environment}, datalake_bucket={datalake_bucket}, schema={schema}, execution_date={execution_date}
        msg=Dataframe imported with sucess.
        """
    )

    load_dataframe_into_datalake(
        df=df_itbi_sp_source,
        environment=environment,
        schema=schema,
        datalake_bucket=datalake_bucket,
        raw_table_name=raw_table_name,
        partition_cols=partition_cols,
    )
  else:
    raise Exception(f"m=Failed to ingest dataframe")

def parse_arguments():
  parser = ArgumentParser(description=JOB_NAME)
  parser.add_argument("env", help="Forno/Prod values")
  parser.add_argument("datalake_bucket", help="Bucket value in forno/prod")
  parser.add_argument("schema", help="Custom Schema to save table"),
  parser.add_argument("table_name", help="Name of the table to store data into")
  parser.add_argument("partitions", help="Partition columns name")
  parser.add_argument("execution_date", help="DAG execution_date")

  args = parser.parse_args()

  env: str = args.env
  datalake_bucket: str = args.datalake_bucket
  schema: str = args.schema
  raw_table_name: str = args.table_name
  partition_cols: List[str] = ast.literal_eval(args.partitions)
  execution_date: str = args.execution_date

  return (
      env,
      datalake_bucket,
      schema,
      raw_table_name,
      partition_cols,
      execution_date,
  )

if __name__ == "__main__":
  main()
