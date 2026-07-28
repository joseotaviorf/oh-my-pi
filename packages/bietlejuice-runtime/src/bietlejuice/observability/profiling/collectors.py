"""Fresh-tier metric collectors (metadata/log-only, Delivery 0).

Table grain: physical/schema/recency signals from DESCRIBE DETAIL + a
stats-served COUNT(*). Partition grain (thin slice): the latest partition's
row count and the rows written by the last commit. Per-partition file/size and
``min_ts``/``max_ts`` recency are deliberately deferred to later deliveries.
"""

from __future__ import annotations

import hashlib
from typing import Any

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.observability.profiling.delta_metadata_reader import (
    DeltaMetadataReader,
)

logger = QuintoAndarLogger("ProfilingCollectors")


def compute_schema_hash(schema_fields: list[dict[str, str]]) -> str:
    """Stable fingerprint of the ordered column name/type list (schema-drift signal)."""
    canonical = ";".join(f"{field['name']}:{field['type']}" for field in schema_fields)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def collect_table_metrics(
    reader: DeltaMetadataReader, database: str, table: str
) -> dict[str, Any]:
    """Table-grain fresh metrics for ``database.table``."""
    fqtn = f"{database}.{table}"
    detail = reader.detail(fqtn)
    schema_fields = reader.schema_fields(fqtn)
    partition_columns = detail.get("partitionColumns") or []
    return {
        "row_count": reader.count(fqtn),
        "num_files": detail.get("numFiles"),
        "size_bytes": detail.get("sizeInBytes"),
        "created_at": detail.get("createdAt"),
        "last_modified": detail.get("lastModified"),
        "latest_partition_value": _latest_partition_spec(
            reader, fqtn, partition_columns
        ),
        "num_columns": len(schema_fields),
        "schema_hash": compute_schema_hash(schema_fields),
        "columns": schema_fields,
        "partition_columns": partition_columns,
        "clustering_columns": detail.get("clusteringColumns") or [],
        "table_properties": detail.get("properties") or {},
        "table_features": detail.get("tableFeatures") or [],
    }


def collect_partition_metrics(
    reader: DeltaMetadataReader,
    database: str,
    table: str,
    partition_columns: list[str],
    last_commit: dict[str, Any] | None,
) -> list[dict[str, Any]]:
    """Partition-grain fresh metrics for the latest partition (thin slice)."""
    if not partition_columns:
        return []
    fqtn = f"{database}.{table}"
    latest_spec = _latest_partition_spec(reader, fqtn, partition_columns)
    if latest_spec is None:
        return []
    return [
        {
            "partition_key": _spec_to_key(latest_spec),
            "row_count": reader.count(fqtn, _spec_to_predicate(latest_spec)),
            "rows_written": _rows_written(last_commit),
            "num_files": None,
            "size_bytes": None,
            "min_ts": None,
            "max_ts": None,
        }
    ]


def _latest_partition_spec(
    reader: DeltaMetadataReader, fqtn: str, partition_columns: list[str]
) -> str | None:
    """Highest partition spec (lexicographic max; date parts are zero-padded).

    Soft-fails to ``None`` when partition listing is unavailable so table-grain
    metrics (row_count, schema_hash, …) still persist — EMR Delta often rejects
    ``SHOW PARTITIONS`` and the reader falls back to DISTINCT when possible.
    """
    if not partition_columns:
        return None
    try:
        specs = reader.partition_specs(fqtn, partition_columns)
    except Exception as error:
        logger.error(
            f"Could not list partitions for {fqtn} (latest_partition_value skipped): {error}"
        )
        return None
    if not specs:
        return None
    return max(specs, key=_partition_spec_sort_key)


def _partition_spec_sort_key(spec: str) -> tuple:
    """Sort key for chronological max (numeric parts compared as ints)."""
    key: list[tuple[int, int | str]] = []
    for item in _spec_to_key(spec):
        value = item["value"]
        try:
            key.append((0, int(value)))
        except ValueError:
            key.append((1, value))
    return tuple(key)


def _spec_to_key(spec: str) -> list[dict[str, str]]:
    """Parse ``year=2026/month=07/day=23`` into name/value structs."""
    parts = [segment for segment in spec.split("/") if "=" in segment]
    key = []
    for segment in parts:
        name, _, value = segment.partition("=")
        key.append({"name": name, "value": value})
    return key


def _spec_to_predicate(spec: str) -> str:
    """Build a SQL predicate for a partition spec (string literals; Spark casts)."""
    key = _spec_to_key(spec)
    return " AND ".join(f"`{item['name']}` = '{item['value']}'" for item in key)


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
