import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from urllib.parse import unquote

from pyspark.sql import DataFrame
from pyspark.sql.functions import col, input_file_name, regexp_extract, udf
from pyspark.sql.types import StringType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_evidently_ml_monitor_raw"
DATE_FMT = "%Y-%m-%d"
PATH_COLUMNS = (
    "source_path",
    "job_name",
    "model_id",
    "model_version",
    "run_folder",
    "run_date_infix",
    "metric_name",
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

DT_PATH_PATTERN = r"dt=([^/]+)"
METRIC_NAME_PATH_PATTERN = r"metric_name=([^/]+)"
JOB_NAME_PATH_PATTERN = r"model-monitoring/([^/]+)/"


def sanitize_metric_name(raw_metric_name: str) -> str:
    if not raw_metric_name:
        return ""
    return unquote(raw_metric_name).lower().replace(" ", "_")


sanitize_metric_name_udf = udf(sanitize_metric_name, StringType())


WIDGET_KEYS_TOP_LEVEL = ("widgets", "tests_widgets")


def strip_widgets(json_data: str) -> str:
    if not json_data:
        return json_data
    try:
        payload = json.loads(json_data)
    except (ValueError, TypeError):
        return json_data
    if not isinstance(payload, dict):
        return json_data
    for key in WIDGET_KEYS_TOP_LEVEL:
        payload.pop(key, None)
    metric_results = payload.get("metric_results")
    if isinstance(metric_results, dict):
        for metric in metric_results.values():
            if isinstance(metric, dict):
                metric.pop("widget", None)
    return json.dumps(payload, separators=(",", ":"))


strip_widgets_udf = udf(strip_widgets, StringType())


def _read_metric_files(spark, source_root: str, file_format: str) -> DataFrame:
    if file_format != "parquet":
        raise ValueError(
            f"Unsupported file format: {file_format}. We expect monitoring data to be saved as parquet files."
        )

    reader = (
        spark.read.option("recursiveFileLookup", "true")
        .option("pathGlobFilter", "*.parquet")
        .option("mergeSchema", "true")
    )
    return reader.format(file_format).load(source_root.rstrip("/"))


def _enrich_path_columns(df: DataFrame) -> DataFrame:
    with_path = df.withColumn("_source_path", input_file_name())
    return (
        with_path.withColumn(
            "dt", regexp_extract(col("_source_path"), DT_PATH_PATTERN, 1)
        )
        .withColumn(
            "_metric_name_raw",
            regexp_extract(col("_source_path"), METRIC_NAME_PATH_PATTERN, 1),
        )
        .filter(col("_metric_name_raw") != "")
        .withColumn(
            "job_name",
            regexp_extract(col("_source_path"), JOB_NAME_PATH_PATTERN, 1),
        )
        .filter(col("job_name") != "")
        .withColumn("metric_name", sanitize_metric_name_udf(col("_metric_name_raw")))
        .drop("_source_path", "_metric_name_raw")
    )


def default_load_end_date(load_start_date: str) -> str:
    dt_start = datetime.strptime(load_start_date, DATE_FMT).date()
    return (dt_start + timedelta(days=1)).strftime(DATE_FMT)


def validate_load_date_range(load_start_date: str, load_end_date: str) -> None:
    dt_start = datetime.strptime(load_start_date, DATE_FMT).date()
    dt_end = datetime.strptime(load_end_date, DATE_FMT).date()
    if dt_start >= dt_end:
        raise ValueError(
            f"load_start_date ({load_start_date}) must be < load_end_date ({load_end_date})"
        )


def _filter_by_date_range(
    df: DataFrame, load_start_date: str, load_end_date: str
) -> DataFrame:
    return df.filter((col("dt") >= load_start_date) & (col("dt") < load_end_date))


def main() -> None:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("bucket")
    parser.add_argument("schema")
    parser.add_argument(
        "load_start_date",
        help="First calendar day to load (inclusive). Format: YYYY-MM-DD",
    )
    parser.add_argument(
        "load_end_date",
        nargs="?",
        default=None,
        help="First calendar day after the load window (exclusive). Format: YYYY-MM-DD",
    )
    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.bucket
    schema = args.schema
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date or default_load_end_date(load_start_date)
    validate_load_date_range(load_start_date, load_end_date)

    table_name = "evidently_ml_monitor"

    logger.info(
        f"m={JOB_NAME}, environment={environment}, schema={schema}, "
        f"datalake_bucket={datalake_bucket}, load_start_date={load_start_date}, "
        f"load_end_date={load_end_date}, msg=Starting spark job..."
    )

    config_service = ConfigurationService("evidently_ml_monitor")

    source_root_path = config_service.get_config("source_root_path")
    file_format = config_service.get_config("format")

    # Initialize clients and services:
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )
    spark_metastore_service.create_database(write_database_name)

    # Read metric files:
    df = _read_metric_files(spark_client.conn, source_root_path, file_format)
    df = _enrich_path_columns(df)
    df = _filter_by_date_range(df, load_start_date, load_end_date)

    row_count = df.count()
    logger.info(
        f"m={JOB_NAME}, load_start_date={load_start_date}, "
        f"load_end_date={load_end_date}, df={row_count}, "
        f"msg=Read and filtered metric files."
    )

    if row_count == 0:
        logger.info(
            f"m={JOB_NAME}, load_start_date={load_start_date}, "
            f"load_end_date={load_end_date}, msg=No data for date range; skipping load."
        )
        return

    df = df.withColumn("json_data", strip_widgets_udf(col("json_data")))

    format_options = SparkTableStorageFormat.DEFAULT_RAW

    s3_path = f"{write_location}{write_table_name}"
    s3_loader.load_df(
        df=df,
        s3_path=s3_path,
        format_options=format_options,
        partitions=None,
        write_mode="append",
    )

    # Sync com a metastore:
    spark_metastore_loader.update_metastore(
        df=df,
        database_name=write_database_name,
        table_name=write_table_name,
        format_options=format_options,
        database_location=write_location,
        partitions=None,
    )

    spark_metastore_service.refresh_table(write_database_name, write_table_name)
    logger.info(
        f"m={JOB_NAME}, table={write_database_name}.{write_table_name}, "
        f"msg=Load completed."
    )


if __name__ == "__main__":
    main()
