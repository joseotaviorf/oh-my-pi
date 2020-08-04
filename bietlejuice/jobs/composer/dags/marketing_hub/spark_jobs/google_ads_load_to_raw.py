import boto3
import logging
import re

from datetime import datetime, timedelta
from unidecode import unidecode
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.s3_consumer import S3Consumer
from bietlejuice.jobs.composer.dags.marketing_hub import SOURCE
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services import S3Service
from pyspark.sql.functions import lit

JOB_NAME = "google_ads_load_to_raw"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

REPORT_TYPES = {
    "ad_performance_report": "ads_performance_report",
    "campaign_performance_report": "campaigns_performance_report",
    "keywords_performance_report": "keywords_performance_report",
}

REPORT_SCHEMAS = {
    "ads_performance_report": [
        "ExternalCustomerId",
        "AdGroupId",
        "AdGroupName",
        "AdType",
        "CampaignId",
        "CampaignName",
        "Clicks",
        "Cost",
        "Date",
        "Description",
        "Description1",
        "Description2",
        "Device",
        "DisplayUrl",
        "Id",
        "Impressions",
        "ImageCreativeName",
        "AccountDescriptiveName",
        "AbsoluteTopImpressionPercentage",
        "ReportType",
    ],
    "campaigns_performance_report": [
        "ExternalCustomerId",
        "CampaignId",
        "CampaignName",
        "Clicks",
        "Cost",
        "Date",
        "Device",
        "Impressions",
        "AccountDescriptiveName",
        "Month",
        "Labels",
        "Week",
        "Year",
        "AbsoluteTopImpressionPercentage",
        "SearchImpressionShare",
        "ReportType",
    ],
    "keywords_performance_report": [
        "ExternalCustomerId",
        "AdGroupId",
        "AdGroupName",
        "CampaignId",
        "CampaignName",
        "Clicks",
        "Cost",
        "Date",
        "Device",
        "Id",
        "Impressions",
        "KeywordMatchType",
        "Labels",
        "Criteria",
        "AccountDescriptiveName",
        "AbsoluteTopImpressionPercentage",
        "SearchImpressionShare",
        "ReportType",
    ],
}
FULL_FILE_PATH_LENGTH = 8


def format_account_name(account_name):
    alphanumeric_account_name = re.sub(r"[^\w\s]", "", account_name)
    snake_cased_account_name = re.sub(r"\s+", "_", alphanumeric_account_name)
    no_accents_account_name = unidecode(snake_cased_account_name)
    return no_accents_account_name.lower()


def split_str(str, split_condition):
    return [x for x in str.split(split_condition) if x != ""]


def get_date(str):
    return re.search("dt=(.*?)/", str).group(1)


def format_date(date):
    formatted_date = datetime.strptime(date, "%d-%m-%Y").strftime("%Y-%m-%d")
    return formatted_date


def get_yesterdays_date(date):
    yesterdays_date = datetime.strptime(date, "%Y-%m-%d").date() - timedelta(days=1)
    return yesterdays_date


def filter_for_full_file_paths(file_paths):
    filtered_file_paths = [
        x for x in file_paths if len(split_str(x, "/")) >= FULL_FILE_PATH_LENGTH
    ]
    return filtered_file_paths


def file_is_from_yesterday(file_path, execution_date):
    formatted_date = format_date(get_date(file_path))
    yesterdays_date = get_yesterdays_date(execution_date)
    return formatted_date == str(yesterdays_date)


def filter_for_execution_date(file_paths, execution_date):
    filtered_file_paths = [
        x for x in file_paths if file_is_from_yesterday(x, execution_date)
    ]
    return filtered_file_paths


def build_target_file_path(s3_file, s3_source_file_path, report_type):
    raw_account_name = s3_file.first().AccountDescriptiveName
    account_name = format_account_name(raw_account_name)
    dt = get_date(s3_source_file_path)
    database_location = f"{s3_file_path_target}/{report_type}/acc={account_name}/"
    table_name = f"dt={dt}"
    return database_location, table_name


def add_schema_to_csv(csv_file, s3_source_file_path, report_type):
    report_schema = REPORT_SCHEMAS[report_type]
    csv_file = csv_file.toDF(*report_schema)
    return csv_file


def convert_csv_to_json(csv_file):
    json_file = csv_file.toJSON()
    return json_file


def get_report_type(s3_path):
    raw_report_type = re.search("report=(.*?)/", s3_source_file_path).group(1).lower()
    parsed_report_type = fix_report_type(raw_report_type)
    return parsed_report_type


def fix_report_type(report_type):
    return REPORT_TYPES[report_type] if report_type in REPORT_TYPES else report_type


def enrich_csv(csv_file, report_type):
    enriched_csv = csv_file.withColumn("ReportType", lit(report_type))
    return enriched_csv


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument(
        "source_path", type=str, help="source path where data will be taken from"
    )
    parser.add_argument(
        "target_path", type=str, help="target path where data will be put"
    )
    parser.add_argument("execution_date")

    args = parser.parse_args()

    s3_file_path_source = args.source_path
    s3_file_path_target = args.target_path
    execution_date = args.execution_date

    logger.info(
        f"m={JOB_NAME}, target_path={s3_file_path_target}, source_path={s3_file_path_source}"
        "msg=print args spark jobs params"
    )

    s3_source_file_format = "csv"
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)

    s3_consumer = S3Consumer(spark_client)
    s3_service = S3Service(boto3.resource("s3"))
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_source_raw_file_paths = s3_service.list_objects(s3_file_path_source)
    s3_source_full_file_paths = filter_for_full_file_paths(s3_source_raw_file_paths)
    s3_source_file_paths = filter_for_execution_date(
        s3_source_full_file_paths, execution_date
    )
    csv_options = {"header": True}

    for s3_source_file_path in s3_source_file_paths:
        csv_s3_file = s3_consumer.get_data_from_file(
            s3_source_file_path, s3_source_file_format, options=csv_options
        )
        report_type = get_report_type(s3_source_file_path)
        enriched_csv_file = enrich_csv(csv_s3_file, report_type)
        csv_s3_file_with_schema = add_schema_to_csv(
            enriched_csv_file, s3_source_file_path, report_type
        )
        s3_target_database_location, s3_target_table_name = build_target_file_path(
            csv_s3_file_with_schema, s3_source_file_path, report_type
        )

        format_options = SparkTableStorageFormat.DEFAULT_RAW
        s3_loader.load_full_table(
            df=csv_s3_file_with_schema,
            database_name=SOURCE,
            table_name=s3_target_table_name,
            database_location=s3_target_database_location,
            format_options=format_options,
        )
        spark_metastore_loader.update_metastore(
            csv_s3_file_with_schema,
            SOURCE,
            s3_target_table_name,
            format_options,
            s3_target_database_location,
        )
