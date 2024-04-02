from argparse import ArgumentParser
from datetime import datetime
from functools import reduce
import json
import logging
import re

from bietlejuice.base.spark import (
    SparkTableStorageFormat,
    BaseDBUtils,
    SparkDataFrameService,
    spark,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.s3_service import S3Service
from bietlejuice.pipeline import IncrementalTableLoaderPipeline
from bietlejuice.base.pipeline import LayerEnum

from quintoandar_logger import QuintoAndarLogger

import boto3
from pyspark.sql.functions import lit
from pyspark.sql.types import StructType, StringType, StructField
from pyspark.sql import DataFrame

JOB_NAME = "load_csv_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def list_files(table_name, source_root_path, format, datetime_to_ingest):
    if format == 'csv':
        s3_files_path = f"{source_root_path}{table_name}"
        files = S3Service(boto3.resource("s3")).list_objects(s3_files_path)
        pattern = re.compile(f".*{datetime_to_ingest.strftime('%Y%m%d')}.*")
        filtered_files = list(filter(pattern.match, files))

    elif format == 'txt':
        s3_files_path = f"{source_root_path}"
        files = S3Service(boto3.resource("s3")).list_objects(s3_files_path)
        pattern = re.compile(f".*{datetime_to_ingest.strftime('%y%m%d')}.*")
        filtered_files = list(filter(pattern.match, files))

    elif format == 'ret_pag':
        s3_files_path = f"{source_root_path}"
        files = S3Service(boto3.resource("s3")).list_objects(s3_files_path)
        pattern = re.compile(f".*{datetime_to_ingest.strftime('_%y%m%d_')}.*")
        filtered_files = list(filter(pattern.match, files))

    elif format == 'ret_cob':
        s3_files_path = f"{source_root_path}"
        files = S3Service(boto3.resource("s3")).list_objects(s3_files_path)
        dt_pattern = '_%d%m%y_' if 'velo' not in s3_files_path else '_%d%m%y'
        pattern = re.compile(f".*{datetime_to_ingest.strftime(dt_pattern)}.*")
        filtered_files = list(filter(pattern.match, files))

    return filtered_files

def generate_schema(col_names: list):
    fields = []
    for col in col_names:
        fields.append(StructField(col, StringType(), True))

    return StructType(fields)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("source_root_path", help="name of the source", default=None)
    parser.add_argument(
        "date_to_ingest",
        help="Date to be used in filtering the files. Format: '%Y-%m-%d'",
    )
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument(
        "consumer_extra_args",
        help="extra arguments to pass to get_data_from_file of S3Consumer",
    )
    parser.add_argument("format", help="file format", default=None)
    parser.add_argument("col_names", help="new names of the columns", default=None)
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    source_root_path = args.source_root_path if args.source_root_path != "None" else None
    date_to_ingest = args.date_to_ingest
    table_name = args.table_name
    consumer_extra_args = json.loads(args.consumer_extra_args)
    partition_cols = ["year", "month", "day"]
    datetime_to_ingest = datetime.strptime(date_to_ingest, "%Y-%m-%d")
    format = args.format if args.format != "None" else None
    col_names = json.loads(args.col_names) if args.col_names != "None" else None



    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                source_root_path={source_root_path}, date_to_ingest={date_to_ingest}, table_name={table_name},
                format={format},col_names={col_names}, consumer_extra_args={consumer_extra_args}, msg=Starting spark job...
        """
    )

    # Initializing clients
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    # Retrieving folders/tables from root location.
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    filtered_files = list_files(table_name, source_root_path, format, datetime_to_ingest)

    if len(filtered_files) > 0:
        if format == 'csv':
            schema = generate_schema(col_names)
            dfs = []

            for file_path in filtered_files:
                df = (
                    spark.read.format("csv")
                    .schema(schema)
                    .option("encoding", "ISO-8859-1")
                    .load(file_path)
                )
                dfs.append(df)

            df = reduce(DataFrame.unionAll, dfs)
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(datetime_to_ingest)
                .output()
            )
        elif format == 'txt':
            dfs = []

            for path in filtered_files:
                df = spark.read.text(path)
                df = df.select(
                    df.value.substr(1,3).alias('id_bank'),
                    df.value.substr(4,4).alias('id_service_batch'),
                    df.value.substr(8,1).alias('record_type'),
                    df.value.substr(9,240).alias('metadata'),

                    )
                df = df.withColumn('file_name', lit(path))
                dfs.append(df)

            df = reduce(DataFrame.unionAll, dfs)
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(datetime_to_ingest)
                .output()
            )

        elif format == 'ret_pag':
            dfs = []

            for path in filtered_files:
                df = spark.read.text(path)
                df = df.select(
                    df.value.substr(1,3).alias('id_bank'),
                    df.value.substr(4,4).alias('id_service_batch'),
                    df.value.substr(8,1).alias('record_type'),
                    df.value.substr(9, 5).alias('record_sequence_number'),
                    df.value.substr(14, 1).alias('segment_type'),
                    df.value.substr(15,225).alias('metadata'),

                    )
                df = df.withColumn('file_name', lit(path))
                dfs.append(df)

            df = reduce(DataFrame.unionAll, dfs)
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(datetime_to_ingest)
                .output()
            )

        elif format == 'ret_cob':
            dfs = []

            for path in filtered_files:
                df = spark.read.text(path)
                df = df.select(
                    df.value.substr(1,1).alias('record_type'),
                    df.value.substr(2,399).alias('metadata'),

                    )
                df = df.withColumn('file_name', lit(path))
                dfs.append(df)

            df = reduce(DataFrame.unionAll, dfs)
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(datetime_to_ingest)
                .output()
            )

        db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

        logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
        database_name = db_info["db_raw_databricks"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        database_location = db_info["db_raw_path"]
        spark_metastore_service.create_database(database_name)

        s3_loader = S3Loader()

        s3_path = f"{database_location}{table_name}"

        IncrementalTableLoaderPipeline(
            database_name,
            table_name,
            database_location,
            LayerEnum.RAW,
            None,
            partition_cols,
        ).load_and_register(df, format_options)

    else:
        logger.warning(
            "m=__main__, msg= No files were found on S3 bucket. Ending process without loading anything."
        )
