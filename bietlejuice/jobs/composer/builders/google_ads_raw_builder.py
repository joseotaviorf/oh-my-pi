from unidecode import unidecode
import re
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from pyspark.sql.functions import col, lit, udf, to_date

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("GoogleAdsRawBuilder")

REPORT_TYPES = {
    "AD_PERFORMANCE_REPORT": "ads_performance_report",
    "CAMPAIGN_PERFORMANCE_REPORT": "campaigns_performance_report",
    "KEYWORDS_PERFORMANCE_REPORT": "keywords_performance_report",
    "VIDEO_PERFORMANCE_REPORT": "videos_performance_report",
}

REPORT_SCHEMAS = {
    "AD_PERFORMANCE_REPORT": [
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
        "acc",
        "dt",
        "ReportType",
    ],
    "CAMPAIGN_PERFORMANCE_REPORT": [
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
        "acc",
        "dt",
        "ReportType",
    ],
    "KEYWORDS_PERFORMANCE_REPORT": [
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
        "acc",
        "dt",
        "ReportType",
    ],
    "VIDEO_PERFORMANCE_REPORT": [
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
        "acc",
        "dt",
        "ReportType",
    ],
}


class GoogleAdsRawBuilder:
    @logger
    def __init__(self, execution_date, source_bucket):
        self.execution_date = execution_date
        self.source_bucket = source_bucket
        self.spark_client = SparkClient()
        self.spark_session = self.spark_client.conn

    @staticmethod
    def format_account_name(account_name):
        alphanumeric_account_name = re.sub(r"[^\w\s]", "", account_name)
        snake_cased_account_name = re.sub(r"\s+", "_", alphanumeric_account_name)
        no_accents_account_name = unidecode(snake_cased_account_name)
        return no_accents_account_name.lower()

    def _read_report_for_today(self, raw_report_type):
        df = (
            self.spark_session.read.option("header", "true")
            .csv(f"s3://{self.source_bucket}/google-reports/report={raw_report_type}")
            .where(
                to_date(col("dt"), "dd-MM-yyyy") == to_date(lit(self.execution_date))
            )
        )
        return df

    def _enrich_report(self, df, raw_report_type):
        udf_format_account_name = udf(self.format_account_name)
        enriched_df = df.withColumn(
            "acc", udf_format_account_name(col("Account"))
        ).withColumn("raw_report_type", lit(REPORT_TYPES[raw_report_type]))
        return enriched_df

    def _rename_enriched_report_columns(self, enriched_df, raw_report_type):
        final_df = enriched_df.toDF(*REPORT_SCHEMAS[raw_report_type])
        return final_df

    def get_report_dataframe(self, raw_report_type):
        df = self._read_report_for_today(raw_report_type)
        enriched_df = self._enrich_report(df, raw_report_type)
        final_df = self._rename_enriched_report_columns(enriched_df, raw_report_type)
        return final_df
