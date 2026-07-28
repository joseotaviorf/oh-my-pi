"""Thin, mockable wrapper over metadata/log-only Delta reads for a table by name.

Every read here is cheap and loader-agnostic: it targets the resulting table
state (Delta log / catalog), never the in-memory write DataFrame, so it works
regardless of how the table was written (DeltaLoader, S3Loader, CDC job).

Row counts use ``SELECT COUNT(*)`` which Delta serves from transaction-log
statistics (deletion-vector correct) and only falls back to a scan when a file
has no stats (e.g. a fresh CONVERT TO DELTA table) — that fallback keeps the
count correct at a higher cost.
"""

from __future__ import annotations

from typing import Any

from delta.tables import DeltaTable
from pyspark.sql import SparkSession


class DeltaMetadataReader:
    """Reads Delta metadata for a fully-qualified table name (``database.table``)."""

    def __init__(self, spark: SparkSession) -> None:
        self.spark = spark

    def _delta_table(self, fqtn: str) -> DeltaTable:
        return DeltaTable.forName(self.spark, fqtn)

    def detail(self, fqtn: str) -> dict[str, Any]:
        """DESCRIBE DETAIL as a dict (numFiles, sizeInBytes, partitionColumns, ...)."""
        return self._delta_table(fqtn).detail().collect()[0].asDict()

    def last_commit(self, fqtn: str) -> dict[str, Any] | None:
        """Most recent commit from DESCRIBE HISTORY, or None when unavailable."""
        rows = self._delta_table(fqtn).history(1).collect()
        if not rows:
            return None
        return rows[0].asDict()

    def schema_fields(self, fqtn: str) -> list[dict[str, str]]:
        """Ordered column name/type pairs used for schema fingerprinting."""
        schema = self.spark.table(fqtn).schema
        return [
            {"name": field.name, "type": field.dataType.simpleString()}
            for field in schema.fields
        ]

    def count(self, fqtn: str, predicate: str | None = None) -> int:
        """Row count served from Delta stats (whole table, or one partition)."""
        query = f"SELECT COUNT(*) FROM {fqtn}"
        if predicate:
            query = f"{query} WHERE {predicate}"
        return int(self.spark.sql(query).collect()[0][0])

    def partition_specs(
        self, fqtn: str, partition_columns: list[str] | None = None
    ) -> list[str]:
        """Partition specs, e.g. ``year=2026/month=07/day=23``.

        Prefers ``SHOW PARTITIONS`` (Hive/catalog partition management). On EMR
        Spark 3.5, many Delta tables reject that command
        (``INVALID_PARTITION_OPERATION.PARTITION_MANAGEMENT_IS_UNSUPPORTED``);
        fall back to ``SELECT DISTINCT`` on the partition columns from the
        Delta log / table data when columns are known.
        """
        try:
            rows = self.spark.sql(f"SHOW PARTITIONS {fqtn}").collect()
            return [row[0] for row in rows]
        except Exception:
            if not partition_columns:
                return []
            cols_sql = ", ".join(f"`{column}`" for column in partition_columns)
            rows = self.spark.sql(f"SELECT DISTINCT {cols_sql} FROM {fqtn}").collect()
            return [
                "/".join(
                    f"{column}={_format_partition_value(column, row[index])}"
                    for index, column in enumerate(partition_columns)
                )
                for row in rows
            ]


def _format_partition_value(column: str, value: object) -> str:
    """Stringify a partition value; zero-pad month/day so specs sort chronologically."""
    if value is None:
        return "null"
    if column in ("month", "day"):
        try:
            return str(int(value)).zfill(2)
        except (TypeError, ValueError):
            pass
    return str(value)
