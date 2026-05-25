import json
import logging
import re
from argparse import ArgumentParser
from datetime import datetime, timedelta
from functools import reduce

import boto3
import pandas as pd
from pyspark.sql import DataFrame
from pyspark.sql.functions import lit
from pyspark.sql.types import StringType, StructField, StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    spark,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.pipeline import IncrementalTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.storage_services.s3_service import S3Service

JOB_NAME = "load_csv_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def list_files(table_name, source_root_path, format, datetime_to_ingest):
    if format == "csv":
        filtered_files = []
        s3_files_path = f"{source_root_path}{table_name}"
        files = S3Service(boto3.resource("s3")).list_objects(s3_files_path)
        for date in datetime_to_ingest:
            pattern = re.compile(f".*{date.strftime('%Y%m%d')}.*")
            filtered_files_list = list(filter(pattern.match, files))
            for file in filtered_files_list:
                filtered_files.append(file)

    elif format == "txt":
        filtered_files = []
        s3_files_path = f"{source_root_path}"
        files = S3Service(boto3.resource("s3")).list_objects(s3_files_path)
        for f in files:
            for date in datetime_to_ingest:
                if any(account in f for account in ["97477", "52081", "98464"]):
                    if date.strftime("_%d%m%y") in f:
                        filtered_files.append(f)
                elif any(account in f for account in ["5514", "130067134"]):
                    if date.strftime("_%d%m%Y_") in f:
                        filtered_files.append(f)
                else:
                    if date.strftime("_%y%m%d_") in f:
                        filtered_files.append(f)

    elif format == "ret_pag":
        filtered_files = []
        s3_files_path = f"{source_root_path}"
        files = S3Service(boto3.resource("s3")).list_objects(s3_files_path)
        for f in files:
            for date in datetime_to_ingest:
                if any(account in f for account in ["426879"]):
                    if date.strftime("_%d%m%y_") in f:
                        filtered_files.append(f)
                else:
                    if date.strftime("_%y%m%d_") in f:
                        filtered_files.append(f)

    elif format == "ret_cob":
        filtered_files = []
        s3_files_path = f"{source_root_path}"
        files = S3Service(boto3.resource("s3")).list_objects(s3_files_path)
        for f in files:
            for date in datetime_to_ingest:
                if any(account in f for account in ["velo"]):
                    if date.strftime("_%d%m%y") in f:
                        filtered_files.append(f)
                elif any(
                    account in f
                    for account in ["063180", "148643", "099036", "469916", "984646"]
                ):
                    if re.search(r"_\d{6}00\.ret$", f):
                        print(f"Ignoring file with invalid date: {f}")
                        continue
                    elif date.strftime("_%d%m%Y_") in f:
                        filtered_files.append(f)
                else:
                    if date.strftime("_%d%m%y_") in f:
                        filtered_files.append(f)
    filtered_files = [f for f in filtered_files if not f.endswith(".rem")]

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
        "load_start_date",
        help="Date to be used in filtering the files. Format: '%Y-%m-%d'",
    )
    parser.add_argument(
        "load_end_date",
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
    source_root_path = (
        args.source_root_path if args.source_root_path != "None" else None
    )
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    table_name = args.table_name
    consumer_extra_args = json.loads(args.consumer_extra_args)
    partition_cols = ["year", "month", "day"]
    load_start_datetime = datetime.strptime(load_start_date, "%Y-%m-%d")
    load_start_datetime = (
        load_start_datetime
        if "recupera" not in source_root_path
        else load_start_datetime + timedelta(days=1)
    )
    load_end_datetime = datetime.strptime(load_end_date, "%Y-%m-%d")
    load_end_datetime = (
        load_end_datetime
        if "recupera" not in source_root_path
        else load_end_datetime + timedelta(days=1)
    )
    datetime_to_ingest = pd.date_range(
        start=load_start_datetime, end=load_end_datetime
    ).tolist()
    format = args.format if args.format != "None" else None
    col_names = json.loads(args.col_names) if args.col_names != "None" else None

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, source_root_path={source_root_path},
                load_start_date={load_start_date}, load_start_datetime={load_start_datetime}, load_end_date={load_end_date}, load_end_datetime={load_end_datetime}, datetime_to_ingest={datetime_to_ingest},
                table_name={table_name}, format={format},col_names={col_names}, consumer_extra_args={consumer_extra_args}, msg=Starting spark job...
        """
    )

    # Initializing clients
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    # Retrieving folders/tables from root location.
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    filtered_files = list_files(
        table_name, source_root_path, format, datetime_to_ingest
    )

    if len(filtered_files) > 0:
        logger.info(
            f"m=__main__, msg= The following files were found for {datetime_to_ingest} and will be loaded: {filtered_files}"
        )

        if format == "csv":
            schema = generate_schema(col_names)
            dfs = []

            for file_path in filtered_files:
                df = (
                    spark.read.format("csv")
                    .schema(schema)
                    .option("encoding", "ISO-8859-1")
                    .load(file_path)
                )
                date_str = re.search(r"_(\d{8})\d{6}\.csv$", file_path).group(1)
                date_obj = datetime.strptime(date_str, "%Y%m%d")
                df = (
                    df.withColumn("file_name", lit(file_path))
                    .withColumn("year", lit(date_obj.year))
                    .withColumn("month", lit(date_obj.month))
                    .withColumn("day", lit(date_obj.day))
                )
                dfs.append(df)

            df = reduce(DataFrame.unionAll, dfs)

        elif format == "txt":
            dfs = []

            for path in filtered_files:
                df = spark.read.text(path)
                df = df.select(
                    df.value.substr(1, 3).alias("id_bank"),
                    df.value.substr(4, 4).alias("id_service_batch"),
                    df.value.substr(8, 1).alias("record_type"),
                    df.value.substr(9, 240).alias("metadata"),
                )
                if any(account in path for account in ["97477", "52081", "98464"]):
                    date_str = re.search(r"_(\d{6})\d+\.ret$", path).group(1)
                    date_obj = datetime.strptime(date_str, "%d%m%y")
                elif any(account in path for account in ["5514", "130067134"]):
                    date_str = re.search(r"_(\d{8})_", path).group(1)
                    date_obj = datetime.strptime(date_str, "%d%m%Y")
                else:
                    date_str = re.search(r"_(\d{6})_\d+\.ret$", path).group(1)
                    date_obj = datetime.strptime(date_str, "%y%m%d")
                df = (
                    df.withColumn("file_name", lit(path))
                    .withColumn("year", lit(date_obj.year))
                    .withColumn("month", lit(date_obj.month))
                    .withColumn("day", lit(date_obj.day))
                )
                dfs.append(df)

            df = reduce(DataFrame.unionAll, dfs)

        elif format == "ret_pag":
            dfs = []

            for path in filtered_files:
                df = spark.read.text(path)
                df = df.select(
                    df.value.substr(1, 3).alias("id_bank"),
                    df.value.substr(4, 4).alias("id_service_batch"),
                    df.value.substr(8, 1).alias("record_type"),
                    df.value.substr(9, 5).alias("record_sequence_number"),
                    df.value.substr(14, 1).alias("segment_type"),
                    df.value.substr(15, 225).alias("metadata"),
                )
                if any(account in path for account in ["426879"]):
                    date_str = re.search(r"_(\d{6})_\d+\.ret$", path).group(1)
                    date_obj = datetime.strptime(date_str, "%d%m%y")
                else:
                    date_str = re.search(r"_(\d{6})_\d+\.ret$", path).group(1)
                    date_obj = datetime.strptime(date_str, "%y%m%d")
                df = (
                    df.withColumn("file_name", lit(path))
                    .withColumn("year", lit(date_obj.year))
                    .withColumn("month", lit(date_obj.month))
                    .withColumn("day", lit(date_obj.day))
                )
                dfs.append(df)

            df = reduce(DataFrame.unionAll, dfs)

        elif format == "ret_cob":
            dfs = []

            for path in filtered_files:
                df = spark.read.text(path)
                df = df.select(
                    df.value.substr(1, 1).alias("record_type"),
                    df.value.substr(2, 399).alias("metadata"),
                )
                if any(
                    account in path
                    for account in ["063180", "148643", "099036", "469916", "984646"]
                ):
                    date_str = re.search(r"_(\d{8})_", path).group(1)
                    date_obj = datetime.strptime(date_str, "%d%m%Y")
                else:
                    date_str = re.search(r"_(\d{6})_\d+\.ret$", path).group(1)
                    date_obj = datetime.strptime(date_str, "%d%m%y")
                df = (
                    df.withColumn("file_name", lit(path))
                    .withColumn("year", lit(date_obj.year))
                    .withColumn("month", lit(date_obj.month))
                    .withColumn("day", lit(date_obj.day))
                )
                dfs.append(df)

            df = reduce(DataFrame.unionAll, dfs)

        db_info = DatalakeMetastoreService.get_db_info(
            environment, source, datalake_bucket
        )
        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

        logger.info(
            "m=__main__, msg=Creating database in Spark Metastore if not exists..."
        )
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
