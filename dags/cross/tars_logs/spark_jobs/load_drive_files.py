import ast
import io
import json
import logging
import sys
from argparse import ArgumentParser
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
from oauth2client.service_account import ServiceAccountCredentials
from pyspark.sql import Row
from pyspark.sql.functions import current_timestamp
from pyspark.sql.types import StringType, StructField, StructType

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_drive_files"
TEMPORARY_DRIVE_FOLDER_ID = "1nlryH4paG-ItEHjRF6NwIuyV5jTCEEw6"
MAX_PARTITIONS = 32
_DRIVE_SCOPES = ["https://www.googleapis.com/auth/drive"]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = logging.getLogger(JOB_NAME)


def _build_drive_client(credentials: dict):
    sa_creds = ServiceAccountCredentials.from_json_keyfile_dict(
        credentials, _DRIVE_SCOPES
    )
    return build("drive", "v3", credentials=sa_creds)


def _get_auth(dbutils) -> dict:
    credentials = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.GSHEETS_CREDENTIALS)
    )
    credentials.pop("scope", None)
    return credentials


def _preflight_check(drive_client, folder_id: str) -> None:
    drive_client.files().get(fileId=folder_id, supportsAllDrives=True).execute()


def _list_modified_files(drive_client, folder_id: str, since_ts: str) -> list:
    query = (
        f"'{folder_id}' in parents"
        f" and trashed=false"
        f" and name contains '.json'"
        f" and modifiedTime > '{since_ts}'"
    )
    files = []
    page_token = None
    while True:
        results = (
            drive_client.files()
            .list(
                q=query,
                fields="nextPageToken, files(id, name)",
                pageSize=100,
                supportsAllDrives=True,
                includeItemsFromAllDrives=True,
                pageToken=page_token,
            )
            .execute()
        )
        files.extend(results.get("files", []))
        page_token = results.get("nextPageToken")
        if not page_token:
            break
    return files


def _copy_to_temp(drive_client, file_id: str, temp_folder_id: str) -> str:
    result = (
        drive_client.files()
        .copy(
            fileId=file_id,
            body={"parents": [temp_folder_id]},
            supportsAllDrives=True,
        )
        .execute()
    )
    return result["id"]


def _download_bytes(drive_client, file_id: str) -> str:
    request = drive_client.files().get_media(fileId=file_id)
    fh = io.BytesIO()
    downloader = MediaIoBaseDownload(fh, request)
    done = False
    while not done:
        _, done = downloader.next_chunk()
    fh.seek(0)
    return fh.read().decode("utf-8")


def _delete_file(drive_client, file_id: str) -> None:
    drive_client.files().delete(fileId=file_id).execute()


def _clear_temp_folder(drive_client) -> None:
    query = f"'{TEMPORARY_DRIVE_FOLDER_ID}' in parents and trashed=false"
    batch = drive_client.new_batch_http_request()
    page_token = None
    while True:
        results = (
            drive_client.files()
            .list(q=query, fields="nextPageToken, files(id)", pageToken=page_token)
            .execute()
        )
        for f in results.get("files", []):
            batch.add(drive_client.files().delete(fileId=f["id"]))
        page_token = results.get("nextPageToken")
        if not page_token:
            break
    batch.execute()


def _download_file_record(
    file_info: dict, credentials: dict, temp_folder_id: str
) -> tuple:
    client = _build_drive_client(credentials)
    file_id = file_info["id"]
    file_name = file_info["name"]
    copy_id = None
    try:
        copy_id = _copy_to_temp(client, file_id, temp_folder_id)
        content = _download_bytes(client, copy_id)
        return (file_name, content, None)
    except Exception as exc:
        return (file_name, None, str(exc))
    finally:
        if copy_id:
            try:
                _delete_file(client, copy_id)
            except Exception as exc:
                logger.warning(
                    f"m=_download_file_record, file_id={file_id}, "
                    f"msg=Failed to delete temp copy: {exc}"
                )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("folder_id")
    parser.add_argument("load_start_date")
    parser.add_argument("partition_columns")
    args = parser.parse_args()
    partition_columns = ast.literal_eval(args.partition_columns)

    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()

    credentials = _get_auth(dbutils)
    drive_client = _build_drive_client(credentials)

    logger.info(
        f"m={JOB_NAME}, folder_id={args.folder_id}, "
        f"load_start_date={args.load_start_date}, msg=Starting pre-flight check..."
    )
    _preflight_check(drive_client, args.folder_id)

    files = _list_modified_files(drive_client, args.folder_id, args.load_start_date)
    logger.info(
        f"m={JOB_NAME}, msg=Found {len(files)} files modified since {args.load_start_date}"
    )

    if not files:
        logger.info(f"m={JOB_NAME}, msg=No files to process. Exiting.")
        sys.exit(0)

    def _worker(file_info):
        return _download_file_record(file_info, credentials, TEMPORARY_DRIVE_FOLDER_ID)

    with ThreadPoolExecutor(max_workers=min(len(files), MAX_PARTITIONS)) as pool:
        results = list(pool.map(_worker, files))

    successes = [(name, content) for name, content, err in results if err is None]
    failures = [(name, err) for name, _, err in results if err is not None]

    if failures:
        failed_names = [name for name, _ in failures]
        logger.error(
            f"m={JOB_NAME}, msg=Failed to download {len(failures)} of {len(files)} files: "
            f"{failed_names}"
        )

    try:
        _clear_temp_folder(drive_client)
    except Exception as exc:
        logger.warning(
            f"m={JOB_NAME}, msg=Temp folder cleanup failed (non-fatal): {exc}"
        )

    if not successes:
        logger.error(
            f"m={JOB_NAME}, msg=All {len(failures)} file downloads failed. Aborting."
        )
        sys.exit(1)

    schema = StructType(
        [
            StructField("file_name", StringType(), True),
            StructField("raw_content", StringType(), True),
        ]
    )
    rows = [Row(file_name=name, raw_content=content) for name, content in successes]
    execution_date = datetime.strptime(args.load_start_date[:10], "%Y-%m-%d")
    df = (
        SparkDataFrameService()
        .input(
            spark.createDataFrame(rows, schema).withColumn(
                "ts_load", current_timestamp()
            )
        )
        .create_year_month_day_columns_from_date(execution_date)
        .output()
    )

    datalake_info = DatalakeMetastoreService.get_db_info(
        args.environment, args.source, args.datalake_bucket
    )
    spark_metastore_service = SparkMetastoreService(spark)
    database_name = datalake_info["db_raw_databricks"]
    database_location = datalake_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{args.table_name}",
        format_options=format_options,
        partitions=partition_columns,
    )
    spark_metastore_loader.update_metastore(
        df,
        database_name,
        args.table_name,
        format_options,
        database_location,
        partition_columns,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=args.table_name,
        df=df,
        partition_cols=partition_columns,
    )

    logger.info(
        f"m={JOB_NAME}, table_name={args.table_name}, "
        f"msg=Successfully loaded {len(successes)} files."
    )
