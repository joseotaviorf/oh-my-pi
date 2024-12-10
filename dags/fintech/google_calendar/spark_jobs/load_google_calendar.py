import ast
import json
import logging
import requests
from argparse import ArgumentParser
from datetime import datetime

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger

from oauth2client.service_account import ServiceAccountCredentials

JOB_NAME = "load_google_calendar"

BASE_CALENDAR_URL = "https://www.googleapis.com/calendar/v3/calendars"
BASE_CALENDAR_ID_FOR_PUBLIC_HOLIDAY = "holiday@group.v.calendar.google.com"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("partition_columns")
    parser.add_argument("calendar_region")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    calendar_region = args.calendar_region
    partition_columns = ast.literal_eval(args.partition_columns)

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
        calendar_region={calendar_region}, partition_columns={partition_columns}"""
        "msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()
    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    secrets = dbutils.secrets.get(scope="quintoandar", key=APIEnum.GOOGLE_CALENDAR)
    credentials = json.loads(secrets, strict=False)
    credentials = ServiceAccountCredentials.from_json_keyfile_dict(
        credentials, "https://www.googleapis.com/auth/calendar.readonly"
    )

    year = datetime.now().year - 1
    url = f"{BASE_CALENDAR_URL}/{calendar_region}%23{BASE_CALENDAR_ID_FOR_PUBLIC_HOLIDAY}/events?timeMin={year}-01-01T00:00:01Z&maxResults=100&orderBy=startTime&singleEvents=true"
    token = credentials.get_access_token().access_token
    headers = {"Authorization": f"Bearer {token}"}

    events = []
    page_token = None
    request_counter = 1
    while True:
        if page_token:
            final_url = f"{url}&syncToken={page_token}"
        else:
            final_url = url
        data = requests.get(f"{url}", headers=headers).json()
        logging.info(
            f"""m={JOB_NAME}, msg= Loading request number: {request_counter}, with size: {len(data.get("items", []))}, and dict_keys: {data.keys()}"""
        )
        events.extend(data.get("items", []))
        page_token = data.get("nextSyncToken", None)
        if not page_token:
            break
        request_counter += 1
    df = spark_client.create_dataframe(events)
    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_date(datetime.now())
        .output()
    )

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_columns,
    )

    spark_metastore_loader.update_metastore(
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_columns,
    )

    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partition_columns,
    )
