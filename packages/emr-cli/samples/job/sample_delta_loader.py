"""
EMR POC: load a small DataFrame via ``DeltaLoader`` (bi-etl-ejuice).

Registration: ``DeltaLoader.load_table`` ends in ``saveAsTable(...)``, which writes Delta
files under ``--target-path`` **and** registers ``--target-table`` in the active metastore
(Glue Data Catalog or Hive), not a path-only write.

Requirements (IAM / Glue):
  - S3 write permission on ``--target-path`` prefix.
  - Glue (or Hive) permission to create/update database for ``--target-table`` and register the table.

Safety:
  - Defaults build synthetic rows only (no reads).
  - Optional ``--source-table`` reads another table; output always goes to ``--target-table``
    at ``--target-path`` — pick a sandbox DB/table you own, never production targets.

This script is a CLI sample, not an Airflow DAG: pass bucket/table identifiers at runtime.

Spark: ``create_emr_spark_session`` plus **sample-only** ``extra_configs`` (S3A routing) to
avoid ``EmrFileSystem`` classpath issues on some EMR bootstrap setups — production
``spark_session_factory`` is unchanged.
"""

from __future__ import annotations

import argparse
import os
from typing import Optional

from pyspark.sql import functions as F

from bietlejuice.base.spark.spark_session_factory import create_emr_spark_session
from bietlejuice.loaders.delta_loader import DeltaLoader
from quintoandar_logger import QuintoAndarLogger


logger = QuintoAndarLogger("EmrSampleDeltaLoader")

# CLI EMR sample only — not applied in ``create_emr_spark_session`` (prod-safe).
# Routes ``s3://`` through S3A + credentials like ``BaseCoreModelSparkJob`` S3A block.
_EMR_SAMPLE_EXTRA_SPARK_CONF = {
    "spark.hadoop.fs.s3.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem",
    "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem",
    "spark.hadoop.fs.s3a.aws.credentials.provider": (
        "com.amazonaws.auth.DefaultAWSCredentialsProviderChain"
    ),
    "spark.hadoop.fs.s3a.path.style.access": "true",
    "spark.hadoop.fs.s3a.connection.maximum": "480",
    "spark.hadoop.fs.s3a.threads.max": "20",
    "spark.hadoop.fs.s3a.connection.timeout": "20000",
    "spark.hadoop.fs.s3a.socket.timeout": "20000",
}


def _prefer_s3a_scheme(path: str) -> str:
    """Use ``s3a://`` so Hadoop resolves via S3A, not EMRFS (``EmrFileSystem``)."""
    p = path.strip()
    if p.startswith("s3://"):
        return "s3a://" + p[len("s3://") :]
    return p


def _env_first(name: str) -> Optional[str]:
    v = os.environ.get(name)
    if v is None or not str(v).strip():
        return None
    return str(v).strip()


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="EMR sample: DeltaLoader write POC.")
    p.add_argument(
        "--target-table",
        default=_env_first("EMR_SAMPLE_TARGET_TABLE"),
        required=_env_first("EMR_SAMPLE_TARGET_TABLE") is None,
        help="Hive/Glue table id: database.table (also EMR_SAMPLE_TARGET_TABLE).",
    )
    p.add_argument(
        "--target-path",
        default=_env_first("EMR_SAMPLE_TARGET_PATH"),
        required=_env_first("EMR_SAMPLE_TARGET_PATH") is None,
        help="S3 prefix for Delta files (s3:// or s3a://; trailing slash optional). "
        "Normalized to s3a:// on EMR to avoid EMRFS classpath issues. "
        "Also EMR_SAMPLE_TARGET_PATH.",
    )
    p.add_argument(
        "--source-table",
        default=_env_first("EMR_SAMPLE_SOURCE_TABLE"),
        help="Optional catalog.table to read (LIMIT applied); "
        "also EMR_SAMPLE_SOURCE_TABLE.",
    )
    p.add_argument(
        "--source-limit",
        type=int,
        default=100,
        help="Max rows when --source-table is set (default 100).",
    )
    p.add_argument(
        "--synthetic-rows",
        type=int,
        default=10,
        help="Row count when no --source-table (default 10).",
    )
    return p.parse_args()


def main() -> None:
    args = _parse_args()
    target_table = args.target_table.strip()
    target_path = _prefer_s3a_scheme(args.target_path.strip()).rstrip("/") + "/"

    if "." not in target_table:
        raise ValueError("target_table must be qualified as database.table")

    spark = create_emr_spark_session(
        "EmrSampleDeltaLoader",
        extra_configs=_EMR_SAMPLE_EXTRA_SPARK_CONF,
    )

    logger.info(
        f"m=main, msg=start, target_table={target_table}, target_path={target_path}"
    )

    if args.source_table:
        src = args.source_table.strip()
        df = spark.table(src).limit(int(args.source_limit))
        logger.info(f"m=main, msg=using_source_table, source_table={src}")
    else:
        n = max(1, int(args.synthetic_rows))
        df = (
            spark.range(0, n)
            .withColumnRenamed("id", "row_id")
            .withColumn("sample_label", F.lit("emr_delta_sample"))
            .withColumn("run_ts", F.current_timestamp())
        )
        logger.info(f"m=main, msg=synthetic_rows, count={n}")

    DeltaLoader(spark=spark).load_table(
        table_name=target_table,
        path=target_path,
        source_df=df,
        partition_by=None,
    )

    logger.info(
        f"m=main, msg=done, target_table={target_table}, path={target_path}, "
        "catalog=saveAsTable_metastore"
    )
    spark.stop()


if __name__ == "__main__":
    main()
