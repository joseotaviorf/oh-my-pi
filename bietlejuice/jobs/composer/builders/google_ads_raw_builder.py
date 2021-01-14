from datetime import datetime
from unidecode import unidecode
import re
from pyspark.sql.functions import lit

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("GoogleAdsRawBuilder")

REPORT_TYPES = {
    "ad_performance_report": "ads_performance_report",
    "campaign_performance_report": "campaigns_performance_report",
    "keywords_performance_report": "keywords_performance_report",
    "video_performance_report": "videos_performance_report",
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
        "acc",
        "dt",
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
        "acc",
        "dt",
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
        "acc",
        "dt",
    ],
    "videos_performance_report": [
        "ExternalCustomerId",
        "AdGroupID",
        "AdGroup",
        "CampaignID",
        "Campaign",
        "Clicks",
        "Cost",
        "Day",
        "Device",
        "Impressions",
        "Account",
        "VideoID",
        "ReportType",
        "acc",
        "dt",
    ],
}
PARTITION_COLUMNS = ["ReportType", "acc", "dt"]


class GoogleAdsRawBuilder:
    @logger
    def __init__(self, s3_consumer, s3_service, execution_date):
        self.s3_consumer = s3_consumer
        self.s3_service = s3_service
        self.s3_source_file_format = "csv"
        self.execution_date = execution_date

    def __get_formatted_account_name(self, raw_account_name):
        account_name = self.__format_account_name(raw_account_name)
        return account_name

    def __format_account_name(self, account_name):
        alphanumeric_account_name = re.sub(r"[^\w\s]", "", account_name)
        snake_cased_account_name = re.sub(r"\s+", "_", alphanumeric_account_name)
        no_accents_account_name = unidecode(snake_cased_account_name)
        return no_accents_account_name.lower()

    def __split_str(self, str, split_condition):
        return [x for x in str.split(split_condition) if x != ""]

    def __get__path_date(self, str):
        return re.search("dt=(.*?)/", str).group(1)

    def __format_path_date(self, date):
        formatted_date = datetime.strptime(date, "%d-%m-%Y").strftime("%Y-%m-%d")
        return formatted_date

    def __parse_execution_date(self, date):
        parsed_date = datetime.strptime(date, "%Y-%m-%d").date()
        return parsed_date

    def __filter_for_full_file_paths(self, file_paths):
        filtered_file_paths = [x for x in file_paths if x[-3:] == ".gz"]
        return filtered_file_paths

    def __file_is_from_today(self, file_path, execution_date):
        path_date = self.__get__path_date(file_path)
        formatted_path_date = self.__format_path_date(path_date)
        parsed_execution_date = self.__parse_execution_date(execution_date)
        return formatted_path_date == str(parsed_execution_date)

    def __filter_for_execution_date(self, file_paths):
        filtered_file_paths = [
            x for x in file_paths if self.__file_is_from_today(x, self.execution_date)
        ]
        return filtered_file_paths

    def __add_schema_to_csv(self, csv_file, s3_source_file_path, report_type):
        report_schema = REPORT_SCHEMAS[report_type]
        csv_file = csv_file.toDF(*report_schema)
        return csv_file

    def __convert_csv_to_json(self, csv_file):
        json_file = csv_file.toJSON()
        return json_file

    def __fix_report_type(self, report_type):
        return REPORT_TYPES[report_type] if report_type in REPORT_TYPES else report_type

    def __add_partition_columns_to_csv(self, csv_file, partitions_tuple):
        enriched_csv = csv_file
        for name, value in partitions_tuple:
            enriched_csv = self.__add_column_to_csv(enriched_csv, name, value)
        return enriched_csv

    def __add_column_to_csv(self, csv_file, name, value):
        enriched_csv_file = csv_file.withColumn(name, lit(value))
        return enriched_csv_file

    def __merge_lists(self, list1, list2):
        merged_list = tuple(zip(list1, list2))
        return merged_list

    def __enrich_csv(self, csv_s3_file, s3_source_file_path, report_type):
        partition_values = self.__get_partition_information(
            csv_s3_file, s3_source_file_path
        )
        partition_values.insert(0, report_type)
        partitions_tuple = self.__merge_lists(PARTITION_COLUMNS, partition_values)
        csv_s3_file_with_partition_columns = self.__add_partition_columns_to_csv(
            csv_s3_file, partitions_tuple
        )
        return csv_s3_file_with_partition_columns

    def __get_partition_information(self, csv_file, s3_file_path):
        account_name = self.__get_formatted_account_name(csv_file.first().Account)
        dt = self.__get__path_date(s3_file_path)
        return [account_name, dt]

    def __check_validity_of_csv(self, csv_file):
        return bool(csv_file and csv_file.first())

    def build_enriched_csv(self, s3_source_file_path, report_type):
        csv_options = {"header": True}
        csv_s3_file = self.s3_consumer.get_data_from_file(
            s3_source_file_path, self.s3_source_file_format, options=csv_options
        )
        is_valid_csv = self.__check_validity_of_csv(csv_s3_file)
        if is_valid_csv:
            enriched_csv_file = self.__enrich_csv(
                csv_s3_file, s3_source_file_path, report_type
            )
            csv_s3_file_with_schema = self.__add_schema_to_csv(
                enriched_csv_file, s3_source_file_path, report_type
            )
            return csv_s3_file_with_schema
        return None

    def build_file_paths(self, s3_file_path_source):
        s3_source_raw_file_paths = self.s3_service.list_objects(s3_file_path_source)
        s3_source_full_file_paths = self.__filter_for_full_file_paths(
            s3_source_raw_file_paths
        )
        s3_source_file_paths = self.__filter_for_execution_date(
            s3_source_full_file_paths
        )
        return s3_source_file_paths

    def build_report_type(self, s3_path):
        raw_report_type = re.search("report=(.*?)/", s3_path).group(1).lower()
        parsed_report_type = self.__fix_report_type(raw_report_type)
        return parsed_report_type

    def build_target_file_path(self, s3_file, s3_file_path_target, report_type):
        account_name = s3_file.first().acc
        dt = s3_file.first().dt
        database_location = f"{s3_file_path_target}/{report_type}/acc={account_name}/"
        table_name = f"dt={dt}"
        return database_location, table_name
