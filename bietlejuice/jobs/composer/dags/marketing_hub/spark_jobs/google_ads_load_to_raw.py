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


JOB_NAME = "google_ads_load_to_raw"
SOURCE = "marketing_hub"
MEDIA = "google_ads"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument(
        "source_path", type=str, help="source path where data will be taken from"
    )
    parser.add_argument(
        "target_path", type=str, help="target path where data will be put"
    )
    parser.add_argument("datalake_bucket", type=str, help="needed to help get db info")
    parser.add_argument("env")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    s3_file_path_source = args.source_path
    s3_file_path_target = args.target_path
    datalake_bucket = args.datalake_bucket
    env = args.env
    execution_date = args.execution_date

    logger.info(
        f"m={JOB_NAME}, target_path={s3_file_path_target}, source_path={s3_file_path_source}"
        "msg=print args spark jobs params"
    )

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)

    s3_consumer = S3Consumer(spark_client)
    s3_service = S3Service(boto3.resource("s3"))
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    google_ads_raw_builder = GoogleAdsRawBuilder(
        s3_consumer, s3_service, execution_date
    )
    s3_source_file_paths = google_ads_raw_builder.build_file_paths(s3_file_path_source)

    db_info = DatalakeMetastoreService.get_db_info(env, SOURCE, datalake_bucket)
    metastore_database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    metastore_database_location = f"{database_location}{MEDIA}/"
    partition_cols = ["acc", "campaign_name", "dt"]

    for s3_source_file_path in s3_source_file_paths:

        try:
            report_type = google_ads_raw_builder.build_report_type(s3_source_file_path)
            enriched_csv_file = google_ads_raw_builder.build_enriched_csv(
                s3_source_file_path, report_type
            )
            (
                s3_target_database_location,
                s3_target_table_name,
            ) = google_ads_raw_builder.build_target_file_path(
                enriched_csv_file, s3_file_path_target, report_type
            )
        except Exception as e:
            logger.info(
                f"m={JOB_NAME}, path={s3_source_file_path} error={e}"
                "msg=no data for this acc on this dt!"
            )

        if s3_target_database_location and s3_target_table_name:
            format_options = SparkTableStorageFormat.DEFAULT_RAW
            s3_loader.load_full_table(
                df=enriched_csv_file,
                database_name=SOURCE,
                table_name=s3_target_table_name,
                database_location=s3_target_database_location,
                format_options=format_options,
            )
            spark_metastore_loader.update_metastore(
                df=enriched_csv_file,
                database_name=metastore_database_name,
                table_name=report_type,
                format_options=format_options,
                database_location=metastore_database_location,
                partitions=partition_cols,
                force_recreate=False,
            )
            spark_metastore_service.create_new_partitions_from_df(
                database_name=metastore_database_name,
                table_name=report_type,
                df=enriched_csv_file,
                partition_cols=partition_cols,
                parallelism=8,
            )
            spark_metastore_service.refresh_table(metastore_database_name, report_type)
