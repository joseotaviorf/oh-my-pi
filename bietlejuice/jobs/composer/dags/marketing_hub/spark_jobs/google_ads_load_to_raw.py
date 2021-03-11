import boto3
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.s3_consumer import S3Consumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services import S3Service
from bietlejuice.jobs.composer.builders import GoogleAdsRawBuilder
from bietlejuice.jobs.composer.base.pipeline import LayerEnum


JOB_NAME = "google_ads_load_to_raw"
SOURCE = "marketing_hub"
MEDIA = "google_ads"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

REPORT_TYPES = {
    "AD_PERFORMANCE_REPORT": "ads_performance_report",
    "CAMPAIGN_PERFORMANCE_REPORT": "campaigns_performance_report",
    "KEYWORDS_PERFORMANCE_REPORT": "keywords_performance_report",
    "VIDEO_PERFORMANCE_REPORT": "videos_performance_report",
}

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("source_bucket", type=str, help="source bucket")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("env")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    source_bucket = args.source_bucket
    datalake_bucket = args.datalake_bucket
    env = args.env
    execution_date = args.execution_date

    logger.info(
        f"m={JOB_NAME}, source_bucket={source_bucket}, "
        f"datalake_bucket={datalake_bucket}, "
        f"execution_date={execution_date}"
        "msg=print args spark jobs params"
    )

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)

    s3_consumer = S3Consumer(spark_client)
    s3_service = S3Service(boto3.resource("s3"))
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    builder = GoogleAdsRawBuilder(execution_date, source_bucket)

    db_info = DatalakeMetastoreService.get_db_info(env, SOURCE, datalake_bucket)
    metastore_database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    metastore_database_location = f"{database_location}{MEDIA}/"
    partition_cols = ["acc", "dt"]
    format_options = SparkTableStorageFormat.get_storage(LayerEnum.RAW.value)

    for report_raw, report in REPORT_TYPES.items():
        df = builder.get_report_dataframe(report_raw)

        s3_loader.load_df(
            df=df,
            format_options=format_options,
            s3_path=metastore_database_location + report,
            partitions=partition_cols,
        )

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df=df,
            database_name=metastore_database_name,
            table_name=report,
            format_options=format_options,
            database_location=metastore_database_location,
            partitions=partition_cols,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=metastore_database_name,
            table_name=report,
            partition_cols=partition_cols,
        )
