from argparse import ArgumentParser, Namespace
from datetime import datetime, timedelta
from google.cloud import storage
import io
import json
import logging
import pandas as pd
from pyspark.sql import DataFrame
from pyspark.sql.functions import lit
from typing import Optional

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline import IncrementalTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_growth_lab_raw"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def main() -> None:
    args = parse_args()
    storage_client = get_storage_client()
    csv_content = get_csv_content_from_gcp_bucket(storage_client, args)
    if csv_content is None:
        return

    try:
        dataframe = get_spark_dataframe_from_csv_content(csv_content)
        load_table_dataframes_into_datalake(dataframe, args)
    except ValueError as e:
        logger.info(f"Empty CSV file. Complete error: {e}")


def get_credentials_dict() -> dict:
    """Returns a dictionary with the credentials to access GCP."""

    auth_str = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.GCP_GROWTH_LAB)
    credentials_dict = json.loads(auth_str).get("token", {})
    credentials_dict["private_key"] = credentials_dict.get("private_key").replace("\\n", "\n")

    return credentials_dict


def get_storage_client() -> storage.Client:
    """Returns a GCP storage client."""

    credentials_dict = get_credentials_dict()
    return storage.Client.from_service_account_info(credentials_dict)


def parse_args() -> Namespace:
    """
    Parse the arguments passed to the script. The resulting namespace has the following attributes:
    - env: environment where the script is running
    - datalake_bucket: name of the datalake bucket where the data will be stored
    - source: name of the source of the data
    - table_name: name of the table where the data will be stored
    - execution_date: date of the execution of the DAG
    - gcp_bucket_name: name of the bucket in GCP
    - prefix_template: template of the file name to find the blob
    """

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("load_start_date", type=str, help="Start of date range to be used in filtering the files")
    parser.add_argument("load_end_date", type=str, help="End of date range to be used in filtering the files")
    parser.add_argument("gcp_bucket_name", type=str, help="Name of the bucket in GCP")
    parser.add_argument("prefix_template", type=str, help="Template of the file name to find the blob")
    args = parser.parse_args()


    parser.add_argument("load_start_date", help="Start of date range to be used in filtering the files. Format: '%Y-%m-%d'")
    parser.add_argument("load_end_date", help="End of date range to be used in filtering the files. Format: '%Y-%m-%d'")

    logger.info(
        f"""
        m=__main__, env={args.env}, datalake_bucket={args.datalake_bucket},
        source={args.source}, table_name={args.table_name}, execution_date={args.execution_date},
        gcp_bucket_name={args.gcp_bucket_name}, prefix_template={args.prefix_template},
        msg=Starting Spark job...
        """
    )

    return args


def get_csv_content_from_gcp_bucket(storage_client: storage.Client, args: Namespace) -> Optional[str]:
    """Returns the content of the CSV file in the GCP bucket"""

    bucket = storage_client.get_bucket(args.gcp_bucket_name)
    prefix = args.prefix_template
    blob = bucket.get_blob(prefix)
    if blob is None:
        logger.info(f"No CSV found in the bucket {args.gcp_bucket_name}, prefix={prefix}")
        return None
    
    logger.info(f"CSV found in the bucket {args.gcp_bucket_name}, prefix={prefix}")

    return blob.download_as_string().decode('UTF-8')


def get_spark_dataframe_from_csv_content(csv_content: str) -> DataFrame:
    """Returns a Spark dataframe from the CSV content"""

    csv_content_stream = io.StringIO(csv_content)
    pd_df = pd.read_csv(csv_content_stream)
    return spark.createDataFrame(pd_df)


def create_date_partitions(df: DataFrame, execution_date_str: str) -> DataFrame:
    """Creates the columns year, month and day using the execution date"""
    
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")
    df = df.withColumn('execution_date', lit(execution_date))

    return (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column('execution_date')
        .output()
    )


def load_table_dataframes_into_datalake(df: DataFrame, args: Namespace) -> None:
    """Loads the dataframes into S3 incrementally"""

    db_info = DatalakeMetastoreService.get_db_info(args.env, args.source, args.datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    partition_cols = ["year", "month", "day"]

    df = create_date_partitions(df, args.execution_date)
    IncrementalTableLoaderPipeline(
        database_name,
        args.table_name,
        database_location,
        LayerEnum.RAW,
        None,
        partition_cols,
    ).load_and_register(df, format_options)


if __name__ == "__main__":
    main()