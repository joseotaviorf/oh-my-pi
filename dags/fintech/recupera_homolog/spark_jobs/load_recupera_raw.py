import json
import os
import logging
import zipfile
from argparse import ArgumentParser
from datetime import datetime
from io import BytesIO

import boto3
from pyspark.sql.functions import current_timestamp
from pyspark.sql.types import StringType, StructField, StructType

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import (BaseDBUtils, SparkDataFrameService,
                                    SparkTableStorageFormat, spark)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.pipeline import (FullTableLoaderPipeline,
                                  IncrementalTableLoaderPipeline)
from bietlejuice.services.metastore_services import SparkMetastoreService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_recupera_homolog_raw"


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def generate_schema(column_names: list):
    """
    Generate schema from csv file based on config file as the original file has no header

    Args:
        column_names (list): the name of the columns

    Returns:
        StructType: the correct schema for the table
    """

    fields = []
    for column in column_names:
        fields.append(StructField(column, StringType(), True))

    return StructType(fields)


def unzip_file(ingestion_date: str, zip_file_bytes: bytes, tmp_folder: str):
    """
    This function is used to correctly read the contents of the S3 object, as the object is a
    compressed csv file (.zip file) protected by password.
    Unzipped content is saved to file in a temporary folder so it can be read using spark.read.csv

    Args:
        ingestion_date (str): the ingestion date used in the password to unzip the file
        zip_file_bytes (bytes): the zipped byte content extracted from the S3 bucket
        tmp_folder (str): folder where the extracted csv files will be saved

    Returns:
        str: the file name
    """

    zip_file_secret = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key="RECUPERA_ZIP_FILE_PASSWORD")
    with zipfile.ZipFile(BytesIO(zip_file_bytes)) as zip_file:
        zip_password = str(zip_file_secret).format(ingestion_date=ingestion_date)
        zip_file.extractall(os.path.join("/dbfs", tmp_folder), pwd=zip_password.encode())
        csv_files_name = zip_file.namelist()
        logger.info(f"m=unzip_file, msg=Files within zip file: {csv_files_name}")
        if len(csv_files_name) > 0:
            return csv_files_name[0]


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("source_root_path", help="name of the source")
    parser.add_argument("date_to_ingest", help="Date to be used in filtering the files. Format: '%Y-%m-%d'",)
    parser.add_argument("table_name", help="translated table name (based on original_table_name)")
    parser.add_argument("extraction_type", help="indicates wheter the load is incremental or not (full)")
    parser.add_argument("partitions", help="table partition")
    parser.add_argument("column_names", help="new names of the columns")
    parser.add_argument("original_table_name", help="the name of the original table, as it is in the Recupera database")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    source_root_path = args.source_root_path
    partition_cols = json.loads(args.partitions)
    date_to_ingest = args.date_to_ingest
    table_name = args.table_name
    original_table_name = args.original_table_name
    extraction_type = json.loads(args.extraction_type)
    column_names = json.loads(args.column_names)

    logger.info(
        f"""m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        source_root_path={source_root_path}, partition_cols= {partition_cols}, date_to_ingest={date_to_ingest},
        table_name={table_name}, original_table_name={original_table_name}, extraction_type = {extraction_type},
        column_names={column_names}, msg=Starting spark job...
        """)

    # Initializing clients
    spark_client = SparkClient()

    # Retrieving folders/tables from root location.
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    tmp_folder = f"tmp/recupera/{table_name}"

    datetime_to_ingest = datetime.strptime(date_to_ingest, "%Y-%m-%d")
    date_to_ingest_formatted = datetime_to_ingest.strftime("%Y%m%d")

    file_path_s3 = f"{source_root_path}/{original_table_name}_{date_to_ingest_formatted}"
    logger.info(f"m=__main__, msg=Looking for pattern: {file_path_s3}.")
    split_s3_path = file_path_s3.split("/")
    bucket_name = split_s3_path[2]
    prefix = "/".join(split_s3_path[3:])

    s3_resource = boto3.resource("s3")
    files_s3 = list(s3_resource.Bucket(bucket_name).objects.filter(Prefix=prefix))

    logger.info(f"m=__main__, msg= Total files found at S3: {files_s3}")
    if len(files_s3) == 0:
        logging.error(f"No object - zip file was found for {file_path_s3})")
        raise Exception(f"No object - zip file was found for {file_path_s3})")

    for s3_object in files_s3:
        print(f"File {os.path.basename(s3_object.key)} was last modified at {s3_object.last_modified}")

    if extraction_type == "full":
        s3_object = sorted(files_s3, key=lambda obj: obj.last_modified, reverse=True)[0]
        list_files_s3 = [f"s3://{bucket_name}/{s3_object.key}"]
    else:
        list_files_s3 = [f"s3://{bucket_name}/{s3_object.key}" for s3_object in files_s3]

    logger.info(f"m=__main__, msg= S3 files to be processed files: {list_files_s3}")

    schema = generate_schema(column_names)

    total_files_df = spark_client.create_dataframe([], schema)

    try:

        for file_path in list_files_s3:
            object_key = "/".join(file_path.split("/")[3:])

            zip_file_content = s3_resource.Bucket(bucket_name).Object(object_key).get()["Body"].read()
            csv_file = unzip_file(date_to_ingest_formatted, zip_file_content, tmp_folder)

            if csv_file is None:
                logger.info(f"""m=__main__, msg=No data was found at file {object_key}""")
                continue

            df = spark.read \
                .option("delimiter", "^") \
                .option("header", "false") \
                .option("encoding", "ISO-8859-1") \
                .option("lineSep", "\r\n") \
                .option("multiLine", "false") \
                .schema(schema) \
                .csv(os.path.join("dbfs:", tmp_folder, csv_file))

            if df.rdd.isEmpty():
                logger.info(f"""m=__main__, msg=No data was found at file {csv_file}""")
                continue

            df.show(5)
            logger.info(f"m=__main__, msg=File: {csv_file}, total Rows : {df.count()}")

            total_files_df = total_files_df.union(df)

        logger.info(f"m=__main__, msg=Total of {total_files_df.count()} rows for table: {table_name} and date: {date_to_ingest}")

        if total_files_df.rdd.isEmpty():
            logger.warning(
                f"""m=__main__, msg=No data was found for table: {table_name} and date: {date_to_ingest}.
                Ending process without loading anything."""
            )
        else:

            total_files_df = (
                SparkDataFrameService()
                .input(total_files_df)
                .create_year_month_day_columns_from_date(datetime_to_ingest)
                .output()
            )

            total_files_df = total_files_df.withColumn("ts_load", current_timestamp())

            db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
            spark_metastore_service = SparkMetastoreService(SparkClient())
            spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

            # create database if it doesn't exists
            database_name = db_info["db_raw_databricks"]
            format_options = SparkTableStorageFormat.DEFAULT_RAW
            database_location = db_info["db_raw_path"]
            spark_metastore_service.create_database(database_name)

            s3_loader = S3Loader()

            if extraction_type == "incremental":
                IncrementalTableLoaderPipeline(
                    database_name=database_name,
                    table_name=table_name,
                    database_location=database_location,
                    layer=LayerEnum.RAW,
                    query=None,
                    partitions=partition_cols,
                ).load_and_register(total_files_df, format_options)
            elif extraction_type == "full":
                FullTableLoaderPipeline(
                    database_name=database_name,
                    table_name=table_name,
                    database_location=database_location,
                    layer=LayerEnum.RAW,
                    query=None
                ).load_and_register(total_files_df, format_options)

    except Exception as error:
        raise error
    finally:
        folder_to_remove = os.path.join("dbfs:", tmp_folder)
        folder_deleted = dbutils.fs.rm(folder_to_remove, True)
        logger.info(f"m=__main__, msg=Folder {folder_to_remove} deleted: {folder_deleted}")
