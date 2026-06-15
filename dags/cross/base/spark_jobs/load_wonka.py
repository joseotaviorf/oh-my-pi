import argparse
import importlib
import logging
import os
import sys

from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
    resolve_datalake_write_target,
)

# Configure the root logger so all modules use the same format
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] {%(filename)s:%(lineno)d} %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[logging.StreamHandler(sys.stdout)],
)

PROD_WONKA_DATABASE = "wonka"
WONKA_VALIDATION_TABLE_PREFIX = "wonka___"


def _validation_s3_bucket_prefix(write_location: str) -> str:
    """Strip s3a:// protocol for FEATURE_STORE_S3_BUCKET (MetastoreConfig format)."""
    return write_location.removeprefix("s3a://").rstrip("/")


def apply_validation_env(
    target_database: str,
    target_table: str,
    bucket: str,
) -> None:
    """Set Wonka writer env vars so pipelines write to cluster_validation targets."""
    prod_table = target_table.split("___", 1)[-1]
    _, _, write_location = resolve_datalake_write_target(
        prod_database=PROD_WONKA_DATABASE,
        prod_table=prod_table,
        prod_location="",
        bucket=bucket,
        target_database=target_database,
        target_table=target_table,
    )
    os.environ["FEATURE_STORE_HISTORICAL_DATABASE"] = target_database
    os.environ["FEATURE_STORE_S3_BUCKET"] = _validation_s3_bucket_prefix(write_location)
    os.environ["WONKA_VALIDATION_TABLE_PREFIX"] = WONKA_VALIDATION_TABLE_PREFIX


def main():
    parser = argparse.ArgumentParser(description="Run a Wonka pipeline.")
    parser.add_argument(
        "pipeline_runner",
        help="The path to the runner of the pipeline, e.g., dummy_feature_set.runner",
    )
    add_validation_target_args(parser)

    args = parser.parse_args()

    if is_validation_run(args.target_database_name, args.target_table_name):
        bucket = os.environ.get("DATABRICKS_S3_BUCKET")
        if not bucket:
            raise RuntimeError(
                "DATABRICKS_S3_BUCKET environment variable is required for "
                "cluster validation runs"
            )
        apply_validation_env(
            args.target_database_name,
            args.target_table_name,
            bucket,
        )

    split_pipeline_runner = args.pipeline_runner.split(".")
    module_path = ".".join(split_pipeline_runner[:-1])
    pipeline_runner_instance_name = split_pipeline_runner[-1]

    module = importlib.import_module(module_path)
    pipeline_runner_instance = getattr(module, pipeline_runner_instance_name)

    pipeline_runner_instance.execute()


if __name__ == "__main__":
    main()
