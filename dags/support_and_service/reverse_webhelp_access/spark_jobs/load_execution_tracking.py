import json
import logging

from argparse import ArgumentParser
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.pipeline import FullTableLoaderPipeline
from bietlejuice.base.spark import (
    BaseDBUtils, 
    SparkTableStorageFormat
)

from datetime import *
from typing import Tuple
from quintoandar_logger import QuintoAndarLogger
from pyspark.sql.types import DataType, StructType
from pyspark.sql.window import Window
from pyspark.sql.functions import *

JOB_NAME = "load_execution_tracking"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def main():
    environment, source, database_name, table_name, azure_container_name, table_context, datalake_bucket, table_schema, execution_date = (
        parse_arguments()
    )
    logger.info(
        f"""m=__main__, environment={environment}, source={source}, database_name={database_name},
        table_name={table_name}, azure_container_name={azure_container_name}, execution_date={execution_date}
        datalake_bucket={datalake_bucket}, table_context={table_context}, table_schema={table_schema}"""
    )

    storage_account_name, storage_account_access_key = get_azure_credentials()
    spark.conf.set(f"fs.azure.account.key.{storage_account_name}.blob.core.windows.net", f"{storage_account_access_key}")
    blob_storage_path = f"wasbs://{azure_container_name}@{storage_account_name}.blob.core.windows.net/"

    df_content = []
    get_dir_content(blob_storage_path, df_content)
    logger.info(f"AZURE DATA: {df_content}")

    dataframe = spark.createDataFrame(data=df_content, schema=table_schema)
    dataframe = dataframe.select(
        col("table_name"), 
        to_date(col("dt_last_updated"),"dd-MM-yyyy").alias("dt_last_updated"),
        col("ts_execution")
    )

    windowDept = Window.partitionBy("table_name").orderBy(col("dt_last_updated").desc())
    dataframe = dataframe.withColumn("row",row_number().over(windowDept)) .filter(col("row") == 1).drop("row")

    logger.info(f"AZURE TRANSFORMED DATA: {dataframe}")
    database_location = f"s3://{datalake_bucket}/reverse/{source}/"

    format_options = SparkTableStorageFormat.DEFAULT_REVERSE

    FullTableLoaderPipeline(
        database_name=database_name,
        table_name=f"{source}_execution_tracking",
        database_location=database_location,
        layer=LayerEnum.REVERSE,
        query=None,
    ).load_and_register(dataframe, format_options)


def parse_arguments() -> Tuple[str, str, str, str, datetime]:
    """
    Parse the arguments passed to the job.
    Returns a tuple with the database name, table name, event type, ARN of the SNS topic and execution date.
    """

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("source")
    parser.add_argument("database_name")
    parser.add_argument("table_name")
    parser.add_argument("azure_container_name")
    parser.add_argument("table_context")
    parser.add_argument("datalake_bucket")
    parser.add_argument("table_schema")
    parser.add_argument(
        "execution_date", help="Date of the execution in the format YYYY-MM-DD"
    )

    args = parser.parse_args()

    environment = args.env
    source = args.source
    database_name = args.database_name
    table_name = args.table_name
    azure_container_name = args.azure_container_name
    table_context = args.table_context
    datalake_bucket = args.datalake_bucket
    execution_date = datetime.fromisoformat(args.execution_date)

    table_schema = json.loads(args.table_schema)
    table_schema = StructType.fromJson(table_schema)

    return environment, source, database_name, table_name, azure_container_name, table_context, datalake_bucket, table_schema, execution_date

def get_azure_credentials():
    DATABRICKS_SCOPE = "quintoandar"
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key="AZURE_WEBHELP"
    )
    credentials = json.loads(json_credentials)

    return credentials['storage_account_name'], credentials['storage_account_access_key']

def get_dir_content(ls_path, tracking_list):
    execution_date = datetime.now()

    for dir_path in dbutils.fs.ls(ls_path):
        if dir_path.isFile():
            try:
                split_dir_path = dir_path.path.split('to_webhelp_')[1].split('/')
                table_name = split_dir_path[0]
                year = split_dir_path[1].split('=')[1]
                month = split_dir_path[2].split('=')[1]
                day = split_dir_path[3].split('=')[1]
                partition_date = datetime.strptime(f"{day}-{month}-{year}", '%d-%m-%Y') + timedelta(1)

                data = (table_name, partition_date.strftime('%d-%m-%Y'), f"{execution_date}")
                logger.info(f"DATA TUPLE: {data}")
                if data:
                    tracking_list.append(data)
            except:
                logger.warn(f"{dir_path.path}")
        elif dir_path.isDir() and ls_path != dir_path.path:
            get_dir_content(dir_path.path, tracking_list)

if __name__ == "__main__":
    main()
