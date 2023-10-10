import boto3
import logging
import json
from bietlejuice.pipeline import FullTableLoaderPipeline
from argparse import ArgumentParser
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import SparkTableStorageFormat
from quintoandar_logger import QuintoAndarLogger
from datetime import *
from pyspark.sql.types import DataType, StructType


JOB_NAME = "load_execution_tracking"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def get_tracking_data(bucket):
    folders = set()
    for obj in bucket.objects.all():
        prefix, delimiter, _ = obj.key.rpartition('/')
        if prefix not in ("from_atento", "to_atento"):
          folders.add(prefix)

    tracking_data = list()
    for folder in folders:
        last_modified_list = list()
        try:
          folder_clean = folder.split("to_atento_")[1]
        except:
          folder_clean = folder.split("/")[1]
        for object_summary in bucket.objects.filter(Prefix=f"{folder}"):
            last_modified_list.append(object_summary.last_modified)
        tracking_data.append((folder_clean, sorted(last_modified_list)[-1], datetime.now()))

    return tracking_data

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values ")
    parser.add_argument("datalake_bucket", help="bucket for forno/prod datalake")
    parser.add_argument("source", help="source name")
    parser.add_argument("external_bucket", help="bucket destination for files")
    parser.add_argument("table_schema", help="Dataframe schema")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    external_bucket = args.external_bucket
    table_schema = json.loads(args.table_schema)
    table_schema = StructType.fromJson(table_schema)

    s3 = boto3.resource('s3')
    bucket = s3.Bucket(external_bucket)

    try:
        tracking_data = get_tracking_data(bucket)

        dataframe = spark.createDataFrame(data=tracking_data, schema=table_schema)

        database_name = f"reverse_{source}"
        database_location = f"s3://{datalake_bucket}/reverse/{source}/"

        format_options = SparkTableStorageFormat.DEFAULT_REVERSE

        FullTableLoaderPipeline(
            database_name=database_name,
            table_name="atento_execution_tracking",
            database_location=database_location,
            layer=LayerEnum.REVERSE,
            query=None,
        ).load_and_register(dataframe, format_options)
    except:
        logger.error(f"An error occurred while trying to save the data.")
