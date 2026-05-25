#!/usr/bin/env python3
import argparse
import ast

from dateutil import parser
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark import SparkTableStorageFormat, spark
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "playwright_release_validations_tests_load"
logger = QuintoAndarLogger(JOB_NAME)
DAG_NAME = "release_validations_tests"


def parse_args() -> argparse.Namespace:
    arg_parser = argparse.ArgumentParser(description=JOB_NAME)
    arg_parser.add_argument("environment", help="forno or prod")
    arg_parser.add_argument(
        "bucket", help="5a-datalake-<env> bucket name or full s3:// path"
    )
    arg_parser.add_argument(
        "schema", help="Schema name without datalake_ prefix or _raw suffix"
    )
    arg_parser.add_argument("table_name", help="Raw table name")
    arg_parser.add_argument("partitions", help="e.g. ['year','month','day']")
    arg_parser.add_argument("execution_date", help="YYYY-MM-DD (data_interval_start)")

    args = arg_parser.parse_args()
    args.partition_cols = ast.literal_eval(args.partitions)
    args.execution_date = parser.parse(args.execution_date)
    return args


def main():
    args = parse_args()
    logger.info(f"[EXECUTION LOGGING] -  args={args}")
    logger.info(
        f"[EXECUTION LOGGING] -  env={args.environment}, bucket={args.bucket}, schema={args.schema}, table={args.table_name}"
    )
    s3_loader = S3Loader()
    conf = ConfigurationService(DAG_NAME)
    path_template = conf.get_config("path")
    date_str = args.execution_date.strftime("%Y-%m-%d")

    source_path = path_template.format(date_str)

    logger.info(f"[EXECUTION LOGGING] -  source_path={source_path}")

    try:
        df_raw = (
            spark.read.format("text")
            .option("wholetext", True)
            .option("recursiveFileLookup", "true")
            .option("pathGlobFilter", "{results,report}.json")
            .load(source_path)
            .selectExpr("_metadata.file_path AS file_path", "value AS content")
        )
    except AnalysisException as e:
        if "PATH_NOT_FOUND" in str(e):
            logger.info(
                f"[EXECUTION LOGGING] -  source_path={source_path}, msg=No data found for this date. Exiting gracefully."
            )
            return
        else:
            logger.error(
                f"[EXECUTION LOGGING] -  source_path={source_path}, msg=Unexpected AnalysisException, error={e}"
            )

    # Pattern for e2e: includes service after ci_build_id
    # s3://bucket/e2e/repository/deploy_group/YYYY-MM-DD/ci_build_id/service/artifacts/results.json
    pattern_e2e = r"^s3[an]?://[^/]+/([^/]+)/([^/]+)/([^/]+)/([0-9]{4}-[0-9]{2}-[0-9]{2})/([^/]+)/([^/]+)/.*/(?:results|report)\.json$"

    # Pattern for hermetic: no service after ci_build_id
    # s3://bucket/hermetic/repository/deploy_group/YYYY-MM-DD/ci_build_id/artifacts/results.json
    pattern_hermetic = r"^s3[an]?://[^/]+/([^/]+)/([^/]+)/([^/]+)/([0-9]{4}-[0-9]{2}-[0-9]{2})/([^/]+)/artifacts/(?:results|report)\.json$"

    df_parsed = df_raw.selectExpr(
        "file_path",
        "content",
        # Determine test_type from both patterns (NULLIF converts empty strings to NULL so COALESCE works as OR)
        f"COALESCE(NULLIF(regexp_extract(file_path, '{pattern_e2e}', 1), ''), NULLIF(regexp_extract(file_path, '{pattern_hermetic}', 1), '')) AS test_type",
        f"COALESCE(NULLIF(regexp_extract(file_path, '{pattern_e2e}', 2), ''), NULLIF(regexp_extract(file_path, '{pattern_hermetic}', 2), '')) AS repository",
        f"COALESCE(NULLIF(regexp_extract(file_path, '{pattern_e2e}', 3), ''), NULLIF(regexp_extract(file_path, '{pattern_hermetic}', 3), '')) AS deploy_group",
        f"COALESCE(NULLIF(regexp_extract(file_path, '{pattern_e2e}', 4), ''), NULLIF(regexp_extract(file_path, '{pattern_hermetic}', 4), '')) AS run_date",
        f"COALESCE(NULLIF(regexp_extract(file_path, '{pattern_e2e}', 5), ''), NULLIF(regexp_extract(file_path, '{pattern_hermetic}', 5), '')) AS ci_build_id",
        # service only exists in e2e pattern
        f"NULLIF(regexp_extract(file_path, '{pattern_e2e}', 6), '') AS service",
        # Extract year, month, day from run_date
        f"CAST(substr(COALESCE(NULLIF(regexp_extract(file_path, '{pattern_e2e}', 4), ''), NULLIF(regexp_extract(file_path, '{pattern_hermetic}', 4), '')), 1, 4) AS INT) AS year",
        f"CAST(substr(COALESCE(NULLIF(regexp_extract(file_path, '{pattern_e2e}', 4), ''), NULLIF(regexp_extract(file_path, '{pattern_hermetic}', 4), '')), 6, 2) AS INT) AS month",
        f"CAST(substr(COALESCE(NULLIF(regexp_extract(file_path, '{pattern_e2e}', 4), ''), NULLIF(regexp_extract(file_path, '{pattern_hermetic}', 4), '')), 9, 2) AS INT) AS day",
        f"((file_path RLIKE '{pattern_e2e}') OR (file_path RLIKE '{pattern_hermetic}')) AS _matched",
    )

    # Create database if not exists
    database_name = f"datalake_{args.schema}_raw"
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)
    logger.info(
        f"[EXECUTION LOGGING] -  database={database_name}, msg=database created or already exists"
    )

    bucket = args.bucket.replace("s3://", "")
    raw_path = f"s3://{bucket}/raw/{args.schema}/{args.table_name}/"
    logger.info(f"[EXECUTION LOGGING] -  raw_path={raw_path}")

    s3_loader.load_df(
        df=df_parsed,
        s3_path=raw_path,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        full_table_name=f"{database_name}.{args.table_name}",
    )

    logger.info("[EXECUTION LOGGING] -  msg=raw load completed")


if __name__ == "__main__":
    main()
