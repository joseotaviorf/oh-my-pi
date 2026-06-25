"""Helpers for legacy Hive metastore partition sync in sync_metadata Spark jobs."""

from __future__ import annotations

from typing import TYPE_CHECKING, Optional

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark.runtime_detector import RuntimeDetector
from bietlejuice.services.metastore_services.glue_partition_utils import (
    is_delta_glue_table,
)

if TYPE_CHECKING:
    from pyspark.sql import SparkSession

logger = QuintoAndarLogger("HiveSyncPartitionUtils")


def is_delta_table_in_catalog(
    database_name: str,
    table_name: str,
    spark: Optional[SparkSession] = None,
) -> bool:
    """Return True when Glue or Spark catalog metadata marks the table as Delta."""
    glue_delta = _lookup_delta_in_glue_catalog(database_name, table_name)
    if glue_delta is not None:
        return glue_delta
    return _is_delta_in_spark_catalog(database_name, table_name, spark)


def should_skip_emr_hive_partition_sync(
    database_name: str,
    table_name: str,
    spark: Optional[SparkSession] = None,
) -> bool:
    """On EMR, Delta tables must not use SHOW PARTITIONS hive-style sync."""
    if not RuntimeDetector.is_emr():
        return False
    if not is_delta_table_in_catalog(database_name, table_name, spark):
        return False
    logger.info(
        f"m=should_skip_emr_hive_partition_sync, table={database_name}.{table_name}, "
        "msg=Delta table on EMR, skipping Hive partition sync"
    )
    return True


def _lookup_delta_in_glue_catalog(
    database_name: str, table_name: str
) -> Optional[bool]:
    """Return Delta status from Glue, or None when Glue has no table metadata."""
    try:
        from bietlejuice.base.spark.glue_catalog_helper import GlueCatalogHelper

        if not GlueCatalogHelper.is_glue_catalog_enabled():
            return None
        glue_table = GlueCatalogHelper.get_glue_client().get_table(
            database_name, table_name
        )
        if glue_table is None:
            return None
        return is_delta_glue_table(glue_table)
    except Exception as exc:
        logger.warning(
            f"m=_lookup_delta_in_glue_catalog, table={database_name}.{table_name}, "
            f"error={exc}, msg=Glue Delta lookup failed, falling back to Spark catalog"
        )
        return None


def _is_delta_in_spark_catalog(
    database_name: str,
    table_name: str,
    spark: Optional[SparkSession],
) -> bool:
    if spark is None:
        return False
    full_table_name = f"{database_name}.{table_name}"
    try:
        from bietlejuice.base.spark.spark_table_property_helper import (
            SparkTablePropertyHelper,
        )

        properties = SparkTablePropertyHelper.get_table_properties(
            full_table_name, spark=spark
        )
        return properties.get("spark.sql.sources.provider") == "delta"
    except Exception as exc:
        logger.warning(
            f"m=_is_delta_in_spark_catalog, table={full_table_name}, "
            f"error={exc}, msg=Spark catalog Delta lookup failed"
        )
        return False
