import json
import re
from argparse import ArgumentParser
from typing import Optional

import boto3
from pyspark.sql.functions import col, input_file_name, lit, regexp_extract
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkDataFrameService
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_amplitude_new_raw"
logger = QuintoAndarLogger(JOB_NAME)


def bucket_from_location(transient_location):
    """Bucket name from an s3 location, e.g. "s3://my-bucket/" -> "my-bucket"."""
    return transient_location.split("//", 1)[1].split("/", 1)[0]


def list_day_object_paths(s3_client, bucket, app_ids, execution_date):
    """Resolve the exact transient object paths for one day via server-side prefix
    listing.

    Replaces the per-app Hadoop glob (``.../{app}/{app}_{date}_*/``), which forces the
    driver to list the entire flat ``{app}/`` prefix (hundreds of thousands of historical
    objects) and filter client-side. ``list_objects_v2`` with the full
    ``{app}/{app}_{date}_`` prefix is served by S3 and scales with the day's object count,
    not the prefix's lifetime history.
    """
    paginator = s3_client.get_paginator("list_objects_v2")
    paths = []
    for app_id in app_ids:
        prefix = f"{app_id}/{app_id}_{execution_date}_"
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                if key.endswith(".json.gz"):
                    paths.append(f"s3://{bucket}/{key}")
    return paths


def extract_app_ids(all_keys):
    """Unique app_ids preserving first-seen order.

    Dedup guards against a secret listing the same app_id twice: the single
    distributed read over list_day_object_paths' output would otherwise union
    the same files twice and inflate row counts (the prior per-app overwrite
    was idempotent).
    """
    return list(dict.fromkeys(key["app_id"] for key in all_keys))


def resolve_raw_database_location(
    write_location: str,
    raw_table_location: Optional[str],
    is_validation: bool,
) -> str:
    """Physical S3 prefix for the raw Delta table (catalog name unchanged).

    Prod runs use ``raw_table_location`` from env conf when set; otherwise a sibling
    ``{prod_raw_path}_delta/`` prefix so Delta is not created on top of legacy JSON.
    Validation runs keep ``write_location`` from ``resolve_datalake_write_target``.
    """
    if is_validation:
        return write_location
    if raw_table_location:
        return (
            raw_table_location
            if raw_table_location.endswith("/")
            else f"{raw_table_location}/"
        )
    return write_location.rstrip("/") + "_delta/"


def main():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")
    add_validation_target_args(parser)
    args = parser.parse_args()

    config_service = ConfigurationService(args.source)
    partition_cols = config_service.get_config("raw_partition_cols")
    table_name = config_service.get_config("table_name")
    transient_location = config_service.get_config("transient_location")
    transient_data_schema = config_service.get_config("transient_data_schema")
    transient_expected_cols = config_service.get_config("transient_expected_cols")

    dbutils = BaseDBUtils().get_dbutils()
    all_keys = json.loads(dbutils.secrets.get("quintoandar", APIEnum.AMPLITUDE) or "[]")
    app_ids = extract_app_ids(all_keys)

    transient_bucket = bucket_from_location(transient_location)
    paths = list_day_object_paths(
        boto3.client("s3"), transient_bucket, app_ids, args.execution_date
    )
    logger.info(
        f"m=main, apps={len(app_ids)}, files={len(paths)}, "
        f"date={args.execution_date}, msg=resolved transient object paths"
    )
    if not paths:
        logger.info(
            "m=main, msg=no transient files for any app on this date; nothing to load"
        )
        return

    spark_client = SparkClient()

    # app is derived from the object path (the authoritative app id) rather than the JSON
    # payload, matching the previous behaviour which overwrote the in-file `app` with the
    # per-prefix app id. A single distributed read over all apps' files spreads the work
    # across the cluster instead of fanning out per-app reads on the driver.
    app_regex = rf"{re.escape(transient_bucket)}/([0-9]+)/"
    df = (
        spark_client.conn.read.schema(transient_data_schema)
        .json(paths)
        .filter(~col("event_type").contains("Exposure"))
        .withColumn("app", regexp_extract(input_file_name(), app_regex, 1).cast("int"))
    )

    df = (
        SparkDataFrameService()
        .input(df)
        .format_column_names()
        .convert_struct_type_to_json()
        .create_year_month_day_columns_from_dataframe_column("server_upload_time")
        .output()
    )

    missing_cols = (c for c in transient_expected_cols if c not in df.columns)
    for table_col in missing_cols:
        df = df.withColumn(table_col, lit(None))

    df = df.select(transient_expected_cols).na.drop(subset=partition_cols)

    # Skip the write when filtering/na.drop leaves no rows. Avoids an unnecessary overwrite
    # (and a static-mode truncate risk).
    if df.isEmpty():
        logger.info("m=main, msg=no rows after filtering this date; skipping write")
        return

    # Write the raw layer as Delta. Delta tracks files/partitions in its transaction log,
    # so downstream reads (the clean step) skip the driver-side S3 partition listing that
    # dominated the legacy JSON read, and gain columnar pruning + stats. Catalog identity
    # stays datalake_{source}_raw.{table_name}; physical files go to raw_table_location
    # (conf) or a derived ``_delta`` sibling prefix so UC does not create Delta on legacy JSON.
    db_info = DatalakeMetastoreService.get_db_info(
        args.environment, args.source, args.datalake_bucket
    )
    write_database, write_table, write_location = resolve_datalake_write_target(
        prod_database=db_info["db_raw_databricks"],
        prod_table=table_name,
        prod_location=db_info["db_raw_path"],
        bucket=args.datalake_bucket,
        target_database=args.target_database_name,
        target_table=args.target_table_name,
    )
    raw_location = resolve_raw_database_location(
        write_location,
        config_service.configs.get("raw_table_location"),
        is_validation_run(args.target_database_name, args.target_table_name),
    )

    # merge_on=None -> overwrite write; with the cluster's dynamic partitionOverwriteMode
    # this replaces only the loaded day's partitions (idempotent per-day re-trigger).
    DataFrameDeltaTableLoaderPipeline(
        database_name=write_database,
        table_name=write_table,
        database_location=raw_location,
        layer="raw",
        dataframe=df,
        partitions=partition_cols,
        merge_on=None,
        spark=spark_client.conn,
    ).run()


if __name__ == "__main__":
    main()
