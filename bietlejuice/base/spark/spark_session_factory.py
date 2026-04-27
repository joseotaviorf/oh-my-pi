"""EMR-only SparkSession builder (Delta + Hive). Databricks keeps injected session."""

from __future__ import annotations

from typing import Any, Dict, Optional

from pyspark.sql import SparkSession


def create_emr_spark_session(
    app_name: str,
    extra_configs: Optional[Dict[str, Any]] = None,
) -> SparkSession:
    builder = (
        SparkSession.builder.appName(app_name)
        .config(
            "spark.sql.extensions",
            "io.delta.sql.DeltaSparkSessionExtension",
        )
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        .config("spark.hadoop.fs.s3a.acl.default", "BucketOwnerFullControl")
        .config("spark.hadoop.fs.s3a.canned.acl", "BucketOwnerFullControl")
        .enableHiveSupport()
    )
    if extra_configs:
        for key, value in extra_configs.items():
            builder = builder.config(key, value)
    return builder.getOrCreate()
