"""EMR-only SparkSession builder (Delta + Hive). Databricks keeps injected session."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from pyspark.sql import SparkSession

_DELTA_SPARK_SQL_EXTENSIONS = "io.delta.sql.DeltaSparkSessionExtension"


def _merge_spark_sql_extensions(*extension_lists: Optional[str]) -> str:
    """Join comma-separated extension class names without duplicates."""
    merged: List[str] = []
    for extension_list in extension_lists:
        if not extension_list:
            continue
        for extension in extension_list.split(","):
            extension = extension.strip()
            if extension and extension not in merged:
                merged.append(extension)
    return ",".join(merged)


def create_emr_spark_session(
    app_name: str,
    extra_configs: Optional[Dict[str, Any]] = None,
) -> SparkSession:
    configs = dict(extra_configs or {})
    cluster_extensions = configs.pop("spark.sql.extensions", None)
    merged_extensions = _merge_spark_sql_extensions(
        _DELTA_SPARK_SQL_EXTENSIONS,
        cluster_extensions,
    )
    builder = (
        SparkSession.builder.appName(app_name)
        .config("spark.sql.extensions", merged_extensions)
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        .config("spark.hadoop.fs.s3a.acl.default", "BucketOwnerFullControl")
        .config("spark.hadoop.fs.s3a.canned.acl", "BucketOwnerFullControl")
        .enableHiveSupport()
    )
    for key, value in configs.items():
        builder = builder.config(key, value)
    return builder.getOrCreate()
