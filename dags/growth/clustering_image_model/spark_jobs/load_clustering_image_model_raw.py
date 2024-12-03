import ast
import logging
import re

from argparse import ArgumentParser
from datetime import datetime, timedelta
from typing import Optional, List

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

from pyspark.sql.functions import lit
from pyspark.sql import DataFrame

from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_clustering_image_model_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def extract_timestamp_from_path(path: str) -> Optional[int]:
  """
  Extracts the unixtimestamp value from the path.

  Args:
    path (str): Path to extract the unixtimestamp value.

  Returns:
    int: Unixtimestamp value extracted from the path.
  """
  match = re.search(r"/([^/]+)/([^/]+)/dedup_output", path)
  unixtimestamp_value = int(match.group(2)) if match and match.group(2).isdigit() else None
  region_name = str(match.group(1)) if match else None
  return unixtimestamp_value, region_name


def convert_unixtimestamp_to_date(ts_unix_value: Optional[int]) -> Optional[datetime]:
  """
  Converts a unixtimestamp value to a datetime object.

  Args:
    ts_unix_value (int): Unixtimestamp value to convert.

  Returns:
    datetime: Datetime object converted from the unixtimestamp value.
  """
  if ts_unix_value:
    return datetime.fromtimestamp(ts_unix_value).date()
  else:
    return None


def is_date_in_range(
  dt_date: Optional[datetime],
  range_date: List[datetime]
  ) -> Optional[bool]:
  """
  Checks if the timestamp date is in the range date.

  Args:
    dt_date (datetime): Date to check.
    range_date (List[datetime]): List of dates to check if the timestamp date is in.

  Returns:
    bool: True if the timestamp date is in the range date, False otherwise.
  """
  return dt_date in range_date if dt_date else None


def create_spark_dataframe(path: str, dt_model: datetime) -> Optional[DataFrame]:
  """
  Creates a spark dataframe from a parquet file.

  Args:
    path (str): Path to the parquet file.
    ts_model (datetime): Datetime object to be added to the dataframe.

  Returns:
    DataFrame: Spark dataframe created from the parquet file.
  """
  try:
    logger.info(f"""
                m=create_spark_dataframe,
                msg=Creating spark dataframe for {path}.
                Reference Date: {dt_model}.
                """)
    df = spark.read.format("parquet").load(path=path)
    logger.info(f"""
                m=create_spark_dataframe,
                msg=Spark dataframe created for {path}.
                Reference Date: {dt_model}.
                Total Rows: {df.count()}
                Total Columns: {len(df.columns)-1}
                """)
    return df
  except Exception as e:
    logger.error(f"""
                 m=create_spark_dataframe,
                 msg=Error creating dataframe for {path}.
                 Exception: {e}.
                 """)


def process_path_data(
  path: str,
  range_date: List[datetime],
  ) -> Optional[DataFrame]:
  """
  Process the data from a path and returns a spark dataframe.

  Args:
    path (str): Path to the parquet file.
    range_date (List[datetime]): List of dates to check if the timestamp date is in.

  Returns:
    DataFrame: Spark dataframe created from the parquet file.
  """
  try:
    ts_unix_value, region_name = extract_timestamp_from_path(path=path)
    dt_model = convert_unixtimestamp_to_date(ts_unix_value=ts_unix_value)
    if dt_model and is_date_in_range(
      dt_date=dt_model,
      range_date=range_date,
      ):
      df = create_spark_dataframe(path=path, dt_model=dt_model)
      if df is None:
        return None
      df = df \
        .withColumn("region_name", lit(region_name)) \
        .withColumn("dt_model", lit(dt_model)) \
        .withColumn("year", lit(dt_model.year)) \
        .withColumn("month", lit(dt_model.month)) \
        .withColumn("day", lit(dt_model.day))
      return df
    else:
      logger.info(f"""
                  m=process_path_data,
                  msg=Folder {path} is invalid.
                  Reference Date: {dt_model}.
                  Range Date: {[date.strftime('%Y-%m-%d') for date in range_date]}.
                  """)
      return None
  except Exception as e:
    logger.error(f"""
                 m=process_path_data,
                 msg=Error processing path: {path}.
                 Exception: {e}.
                 """)


def load_dataframe_into_datalake(
  datalake_bucket: str,
  df: DataFrame,
  environment: str,
  partition_cols: List[str],
  raw_table_name: str,
  source: str
  ) -> None:
  """
  Loads a spark dataframe into the datalake.

  Args:
    datalake_bucket (str): Datalake bucket to store the data.
    df (DataFrame): Spark dataframe to store in the datalake.
    environment (str): Environment to store the data.
    partition_cols (List[str]): List of partition columns to store the data.
    raw_table_name (str): Name of the table to store the data into.
    source (str): Source of the data.

  Returns:
    None
  """
  spark_client = SparkClient()

  db_info = DatalakeMetastoreService.get_db_info(
    env=environment,
    source=source,
    bucket=datalake_bucket
  )

  database_name = db_info["db_raw_databricks"]
  database_location = db_info["db_raw_path"]
  format_options = SparkTableStorageFormat.DEFAULT_RAW

  s3_loader = S3Loader()
  spark_metastore_service = SparkMetastoreService(spark_client)
  spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

  spark_metastore_service.create_database(database_name=database_name)

  s3_loader.load_df(
    df=df,
    s3_path=f"{database_location}{raw_table_name}",
    format_options=format_options,
    partitions=partition_cols,
    max_records_per_file=250000,
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
  # Parse parameters
  parser = ArgumentParser(description=JOB_NAME)
  parser.add_argument("environment", help="Forno/Prod values")
  parser.add_argument("datalake_bucket", help="Bucket value in forno/prod")
  parser.add_argument("source", help="DAG name")
  parser.add_argument("table_name", help="Name of the table to store data into")
  parser.add_argument("partitions", help="Partition columns name")
  parser.add_argument("base_path", help="Data Science S3 bucket path to read data from")
  parser.add_argument("path_key", help="Key to identify the dedup output path")
  parser.add_argument("region_list", help="List of regions to process")
  parser.add_argument("load_start_date", help="Start date to load data")
  parser.add_argument("load_end_date", help="End date to load data")

  args = parser.parse_args()

  # Ingestion parameters
  environment: str = args.environment
  datalake_bucket: str = args.datalake_bucket
  source: str = args.source
  raw_table_name: str = args.table_name
  partition_cols: List[str]  = ast.literal_eval(args.partitions)
  # Extraction parameters
  base_path: str = args.base_path
  path_key: str = args.path_key
  region_list: List[str] = ast.literal_eval(args.region_list)
  load_start_date: datetime = datetime.strptime(
    args.load_start_date,
    "%Y-%m-%d"
  ).date()
  load_end_date: datetime = datetime.strptime(
    args.load_end_date,
    "%Y-%m-%d"
  ).date()

  range_date: List[datetime] = [
    load_start_date + timedelta(days=x) for x in range(
      (load_end_date - load_start_date).days + 1
      )
  ]

  logger.info(f"""
          m=main, environment={environment}, datalake_bucket={datalake_bucket},
          source={source}, raw_table_name={raw_table_name},
          partition_cols={partition_cols}.
          base_path={base_path}, region_list={region_list},
          load_start_date={load_start_date}, load_end_date={load_end_date}.
          msg=Starting Spark Job...
          """)

  # Instance dbutils
  base_dbutils = BaseDBUtils()

  if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()

  for region_name in region_list:
    path_region = f"{base_path}{region_name}/"
    for unixtimestamp_folder in dbutils.fs.ls(path_region):
      dedup_output_path = f"{unixtimestamp_folder.path}{path_key}"
      df_model = process_path_data(path=dedup_output_path,
                                   range_date=range_date,
                                   )
      if df_model:
        load_dataframe_into_datalake(
          df=df_model,
          datalake_bucket=datalake_bucket,
          environment=environment,
          partition_cols=partition_cols,
          raw_table_name=raw_table_name,
          source=source,
        )
      else:
        logger.info(f"""
                    m=main,
                    msg=No valid data for {path_region}.
                    """)


if __name__ == "__main__":
  main()
