"""Fresh-tier metric collectors (metadata/log-only, Delivery 0).

Table grain: physical/schema signals from DESCRIBE DETAIL, row counts from Delta
log stats (fallback COUNT), and the chronologically latest partition that still
has rows. Partition grain: the run-day partition's total row count and rows
written by the last commit (SLA input — separate from table-grain recency).
"""

from __future__ import annotations

import hashlib
from typing import Any

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.observability.profiling.constants import CollectionMethod
from bietlejuice.observability.profiling.delta_metadata_reader import (
    DeltaMetadataReader,
    partition_key_from_logical_date,
    partition_key_to_predicate,
)

logger = QuintoAndarLogger("ProfilingCollectors")


def compute_schema_hash(schema_fields: list[dict[str, str]]) -> str:
    """Stable fingerprint of the ordered column name/type list (schema-drift signal)."""
    canonical = ";".join(f"{field['name']}:{field['type']}" for field in schema_fields)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def collect_table_metrics(
    reader: DeltaMetadataReader,
    database: str,
    table: str,
) -> dict[str, Any]:
    """Table-grain fresh metrics for ``database.table``."""
    fqtn = f"{database}.{table}"
    detail = reader.detail(fqtn)
    schema_fields = reader.schema_fields(fqtn)
    partition_columns = detail.get("partitionColumns") or []
    row_count, stats_complete = reader.row_count_from_log(fqtn)
    collection_method = CollectionMethod.SPARK_LOG.value
    if not stats_complete or row_count is None:
        row_count = reader.count(fqtn)
        collection_method = CollectionMethod.SPARK_COUNT_FALLBACK.value
    latest_partition_value = reader.latest_partition_with_data_from_log(
        fqtn, partition_columns
    )
    return {
        "row_count": row_count,
        "num_files": detail.get("numFiles"),
        "size_bytes": detail.get("sizeInBytes"),
        "created_at": detail.get("createdAt"),
        "last_modified": detail.get("lastModified"),
        "latest_partition_value": latest_partition_value,
        "num_columns": len(schema_fields),
        "schema_hash": compute_schema_hash(schema_fields),
        "columns": schema_fields,
        "partition_columns": partition_columns,
        "clustering_columns": detail.get("clusteringColumns") or [],
        "table_properties": detail.get("properties") or {},
        "table_features": detail.get("tableFeatures") or [],
        "collection_method": collection_method,
    }


def collect_partition_metrics(
    reader: DeltaMetadataReader,
    database: str,
    table: str,
    partition_columns: list[str],
    last_commit: dict[str, Any] | None,
    run_logical_date: str,
) -> list[dict[str, Any]]:
    """Partition-grain fresh metrics for the run-day partition."""
    if not partition_columns:
        return []
    partition_key = partition_key_from_logical_date(run_logical_date, partition_columns)
    if partition_key is None:
        logger.warning(
            f"Skipping partition metrics for {database}.{table}: cannot map "
            f"run_logical_date={run_logical_date} to partition columns "
            f"{partition_columns}"
        )
        return []
    fqtn = f"{database}.{table}"
    row_count, stats_complete = reader.partition_row_count_from_log(fqtn, partition_key)
    collection_method = CollectionMethod.SPARK_LOG.value
    if not stats_complete or row_count is None:
        row_count = reader.count(fqtn, partition_key_to_predicate(partition_key))
        collection_method = CollectionMethod.SPARK_COUNT_FALLBACK.value
    return [
        {
            "partition_key": partition_key,
            "row_count": row_count,
            "rows_written": _rows_written(last_commit),
            "num_files": None,
            "size_bytes": None,
            "min_ts": None,
            "max_ts": None,
            "collection_method": collection_method,
        }
    ]


def _rows_written(last_commit: dict[str, Any] | None) -> int | None:
    """Rows written by the last commit (numOutputRows), or None when unknown."""
    if not last_commit:
        return None
    metrics = last_commit.get("operationMetrics") or {}
    raw = metrics.get("numOutputRows")
    if raw is None:
        return None
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None
