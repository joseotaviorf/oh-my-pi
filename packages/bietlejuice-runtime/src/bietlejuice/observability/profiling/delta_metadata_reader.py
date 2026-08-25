"""Thin, mockable wrapper over metadata/log-only Delta reads for a table by name.

Every read here is cheap and loader-agnostic: it targets the resulting table
state (Delta log / catalog), never the in-memory write DataFrame, so it works
regardless of how the table was written (DeltaLoader, S3Loader, CDC job).

Row counts prefer summing ``numRecords`` from the active Delta snapshot
(transaction log). When any active file lacks stats, callers fall back to
``SELECT COUNT(*)`` (partition-pruned when a predicate is supplied).

**Limitation (deletion vectors):** ``numRecords`` on AddFile is physical at
write time and does not subtract deletion vectors. Log-first counts can therefore
overstate logical row counts (and mark a partition as non-empty) relative to a
DV-aware ``SELECT COUNT(*)``. Accepted for this delivery; revisit if empty-
partition SLA false negatives appear on DV-enabled tables.
"""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any, Optional

from delta.tables import DeltaTable
from pyspark.sql import DataFrame, SparkSession
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("DeltaMetadataReader")

_STANDARD_DATE_PARTITION_COLUMNS = frozenset({"year", "month", "day"})

# (partitionValues, numRecords) per active AddFile; numRecords None => missing stats.
# Optional (not ``int | None``): this alias is evaluated at import time, which fails
# on EMR Python 3.9 despite ``from __future__ import annotations``.
_ActiveFiles = list[tuple[dict[str, str], Optional[int]]]


class DeltaMetadataReader:
    """Reads Delta metadata for a fully-qualified table name (``database.table``)."""

    def __init__(self, spark: SparkSession) -> None:
        self.spark = spark
        # One snapshot collect per FQTN per reader lifetime (table + partition grains).
        self._active_files_cache: dict[str, _ActiveFiles] = {}
        self._active_file_stats_cache: dict[str, list[dict[str, Any] | None]] = {}

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

    def row_count_from_log(self, fqtn: str) -> tuple[int | None, bool]:
        """Table-grain row count from active-file stats in the Delta snapshot."""
        try:
            return _sum_num_records(self._active_files(fqtn))
        except Exception as error:
            logger.warning(
                f"Could not read table row_count from log for {fqtn}: {error}"
            )
            return None, False

    def partition_row_count_from_log(
        self, fqtn: str, partition_key: list[dict[str, str]]
    ) -> tuple[int | None, bool]:
        """Partition-grain row count from active-file stats for ``partition_key``."""
        try:
            target = partition_values_map(partition_key)
            return _sum_num_records(self._active_files(fqtn), target=target)
        except Exception as error:
            logger.warning(
                f"Could not read partition row_count from log for {fqtn}: {error}"
            )
            return None, False

    def has_deletion_vectors(self, fqtn: str) -> bool:
        """True when the table enables deletion vectors (stats may be unreliable)."""
        try:
            detail = self.detail(fqtn)
        except Exception as error:
            logger.warning(f"Could not read detail for {fqtn}: {error}")
            return True
        features = detail.get("tableFeatures") or []
        return "deletionVectors" in features

    def max_column_from_log(
        self, fqtn: str, column: str
    ) -> tuple[datetime | None, bool]:
        """Latest value for ``column`` from active-file stats maxValues."""
        try:
            self._active_files(fqtn)
            stats_payloads = self._active_file_stats_cache.get(fqtn, [])
            return _max_column_from_stats(stats_payloads, column)
        except Exception as error:
            logger.warning(
                f"Could not read max column from log for {fqtn}.{column}: {error}"
            )
            return None, False

    def max_column_fallback(self, fqtn: str, column: str) -> datetime | None:
        """``SELECT MAX(column)`` fallback when log stats are incomplete."""
        quoted = _quote_identifier(column)
        query = f"SELECT MAX({quoted}) AS max_value FROM {fqtn}"
        raw = self.spark.sql(query).collect()[0]["max_value"]
        return _parse_timestamp_value(raw)

    def is_temporal_column(self, fqtn: str, column: str) -> bool:
        """True when ``column`` exists and is date or timestamp typed."""
        for field in self.schema_fields(fqtn):
            if field.get("name") != column:
                continue
            data_type = str(field.get("type") or "").lower()
            return data_type.startswith("timestamp") or data_type == "date"
        return False

    def latest_partition_with_data_from_log(
        self, fqtn: str, partition_columns: list[str]
    ) -> str | None:
        """Latest ``year``/``month``/``day`` partition that has rows, from log stats.

        Returns a Hive-style spec (``year=YYYY/month=MM/day=DD``) or ``None`` when
        the table is unpartitioned / non-standard, has no partition with confirmed
        ``numRecords > 0``, or the snapshot cannot be read. Does not run
        ``SHOW PARTITIONS`` / ``SELECT DISTINCT``.
        """
        if set(partition_columns) != _STANDARD_DATE_PARTITION_COLUMNS:
            return None
        try:
            return _latest_partition_spec_with_data(
                self._active_files(fqtn), partition_columns
            )
        except Exception as error:
            logger.warning(
                f"Could not read latest partition with data from log for {fqtn}: "
                f"{error}"
            )
            return None

    def _active_files(self, fqtn: str) -> _ActiveFiles:
        """Active AddFiles for ``fqtn``; cached once per reader instance."""
        cached = self._active_files_cache.get(fqtn)
        if cached is not None:
            return cached
        files_df = self._all_files_dataframe(fqtn)
        rows = files_df.select("partitionValues", "stats").collect()
        active_files: _ActiveFiles = []
        stats_payloads: list[dict[str, Any] | None] = []
        for row in rows:
            partition_values = _row_partition_values(row["partitionValues"])
            active_files.append((partition_values, _parse_num_records(row["stats"])))
            stats_payloads.append(_parse_stats_payload(row["stats"]))
        self._active_files_cache[fqtn] = active_files
        self._active_file_stats_cache[fqtn] = stats_payloads
        return active_files

    def _all_files_dataframe(self, fqtn: str) -> DataFrame:
        """Active AddFile rows from the current Delta snapshot (OSS + Databricks).

        Uses ``DataFrame(snapshot.allFiles(), spark)``. Validated on Databricks
        forno with ``collection_method=spark_log``; EMR/OSS ``toDF()`` not changed
        until a failed run proves the wrap path breaks there.
        """
        snapshot = self._delta_snapshot(fqtn)
        return DataFrame(snapshot.allFiles(), self.spark)

    def _delta_snapshot(self, fqtn: str) -> Any:
        """Resolve a Delta snapshot via DeltaTable JVM handle, then OSS/Tahoe DeltaLog."""
        try:
            return self._snapshot_from_delta_table(fqtn)
        except Exception as delta_table_error:
            logger.debug(
                f"DeltaTable snapshot unavailable for {fqtn}: {delta_table_error}"
            )
        location = self.detail(fqtn).get("location")
        if not location:
            raise ValueError(f"Delta table location missing for {fqtn}")
        return self._snapshot_from_delta_log(location)

    def _snapshot_from_delta_table(self, fqtn: str) -> Any:
        """Preferred path: Java DeltaTable already resolved by the Python API."""
        jdelta_table = self._delta_table(fqtn)._jdt
        delta_log = jdelta_table.deltaLog()
        return self._snapshot_from_log_handle(delta_log)

    def _snapshot_from_delta_log(self, location: str) -> Any:
        """Fallback for environments where DeltaTable.deltaLog() is unavailable."""
        jvm = self.spark._jvm
        jspark = self.spark._jsparkSession
        candidates = (
            "org.apache.spark.sql.delta.DeltaLog",  # OSS / EMR delta-spark
            "com.databricks.sql.transaction.tahoe.DeltaLog",  # Databricks Runtime
        )
        last_error: Exception | None = None
        for class_name in candidates:
            try:
                delta_log_cls = self._jvm_class(class_name)
                path = jvm.org.apache.hadoop.fs.Path(str(location))
                try:
                    delta_log = delta_log_cls.forTable(jspark, path)
                except Exception:
                    delta_log = delta_log_cls.forTable(jspark, str(location))
                return self._snapshot_from_log_handle(delta_log)
            except Exception as error:
                last_error = error
                continue
        raise RuntimeError(
            f"Could not open DeltaLog for location={location}: {last_error}"
        )

    def _snapshot_from_log_handle(self, delta_log: Any) -> Any:
        """Get a readable snapshot from a JVM DeltaLog (API differs OSS vs DBR)."""
        errors: list[str] = []
        for method_name in ("unsafeVolatileSnapshot", "snapshot", "update"):
            try:
                method = getattr(delta_log, method_name)
                snapshot = method()
                if snapshot is not None:
                    return snapshot
            except Exception as error:
                errors.append(f"{method_name}: {error}")
        # Some DBR builds expose snapshot as a field/property, not a method.
        try:
            snapshot = delta_log.snapshot()
            if snapshot is not None:
                return snapshot
        except Exception as error:
            errors.append(f"snapshot_property: {error}")
        raise RuntimeError("; ".join(errors) or "no snapshot accessor worked")

    def _jvm_class(self, class_name: str) -> Any:
        """Resolve a JVM class/companion via py4j without returning a bare JavaPackage."""
        jvm = self.spark._jvm
        current: Any = jvm
        for part in class_name.split("."):
            current = getattr(current, part)
        if current.__class__.__name__ == "JavaPackage":
            raise AttributeError(f"JVM class not found: {class_name}")
        return current


def partition_key_from_logical_date(
    run_logical_date: str, partition_columns: list[str]
) -> list[dict[str, str]] | None:
    """Build a partition key for ``year``/``month``/``day`` tables from Airflow date."""
    if set(partition_columns) != _STANDARD_DATE_PARTITION_COLUMNS:
        return None
    try:
        parsed = datetime.strptime(run_logical_date, "%Y-%m-%d")
    except ValueError:
        return None
    values = {
        "year": str(parsed.year),
        "month": _format_partition_value("month", parsed.month),
        "day": _format_partition_value("day", parsed.day),
    }
    return [{"name": column, "value": values[column]} for column in partition_columns]


def partition_values_map(partition_key: list[dict[str, str]]) -> dict[str, str]:
    return {item["name"]: item["value"] for item in partition_key}


def partition_key_to_spec(partition_key: list[dict[str, str]]) -> str:
    return "/".join(f"{item['name']}={item['value']}" for item in partition_key)


def partition_key_to_predicate(partition_key: list[dict[str, str]]) -> str:
    return " AND ".join(
        f"`{item['name']}` = '{item['value']}'" for item in partition_key
    )


def _sum_num_records(
    active_files: list[tuple[dict[str, str], int | None]],
    *,
    target: dict[str, str] | None = None,
) -> tuple[int | None, bool]:
    filtered = active_files
    if target is not None:
        filtered = [
            (partition_values, num_records)
            for partition_values, num_records in active_files
            if _partition_values_match(partition_values, target)
        ]
    if not filtered:
        return 0, True
    total = 0
    for _, num_records in filtered:
        if num_records is None:
            return None, False
        total += num_records
    return total, True


def _latest_partition_spec_with_data(
    active_files: list[tuple[dict[str, str], int | None]],
    partition_columns: list[str],
) -> str | None:
    """Pick the chronologically latest year/month/day partition with rows > 0."""
    groups: dict[tuple[str, ...], list[int | None]] = {}
    for partition_values, num_records in active_files:
        if not all(column in partition_values for column in partition_columns):
            continue
        key = tuple(
            _format_partition_value(column, partition_values[column])
            for column in partition_columns
        )
        groups.setdefault(key, []).append(num_records)

    with_data: list[tuple[str, ...]] = []
    for key, records in groups.items():
        known = [record for record in records if record is not None]
        if any(record is None for record in records):
            # Incomplete stats: still treat as having data if any known count > 0.
            if any(record > 0 for record in known):
                with_data.append(key)
            continue
        if sum(known) > 0:
            with_data.append(key)

    if not with_data:
        return None

    def _chronological_key(key: tuple[str, ...]) -> tuple[int, ...]:
        values = dict(zip(partition_columns, key))
        return tuple(int(values[column]) for column in ("year", "month", "day"))

    best = max(with_data, key=_chronological_key)
    partition_key = [
        {"name": column, "value": value}
        for column, value in zip(partition_columns, best)
    ]
    return partition_key_to_spec(partition_key)


def _partition_values_match(actual: dict[str, str], target: dict[str, str]) -> bool:
    for name, expected in target.items():
        if name not in actual:
            return False
        if not _values_equal(name, actual[name], expected):
            return False
    return True


def _values_equal(column: str, actual: str, expected: str) -> bool:
    if column in ("year", "month", "day"):
        try:
            return int(actual) == int(expected)
        except (TypeError, ValueError):
            pass
    return str(actual) == str(expected)


def _parse_num_records(stats: object) -> int | None:
    if stats is None:
        return None
    if isinstance(stats, dict):
        raw = stats.get("numRecords")
    else:
        try:
            payload = json.loads(str(stats))
        except (TypeError, ValueError, json.JSONDecodeError):
            return None
        if not isinstance(payload, dict):
            return None
        raw = payload.get("numRecords")
    if raw is None:
        return None
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


def _row_partition_values(raw: object) -> dict[str, str]:
    if raw is None:
        return {}
    if hasattr(raw, "asDict"):
        values = raw.asDict()
    elif isinstance(raw, dict):
        values = raw
    else:
        return {}
    return {str(key): str(value) for key, value in values.items()}


def _format_partition_value(column: str, value: object) -> str:
    """Stringify a partition value; zero-pad month/day for canonical year/month/day keys."""
    if value is None:
        return "null"
    if column in ("month", "day"):
        try:
            return str(int(value)).zfill(2)
        except (TypeError, ValueError):
            pass
    return str(value)


def _quote_identifier(name: str) -> str:
    escaped = str(name).replace("`", "``")
    return f"`{escaped}`"


def _parse_stats_payload(stats: object) -> dict[str, Any] | None:
    if stats is None:
        return None
    if isinstance(stats, dict):
        return stats
    try:
        payload = json.loads(str(stats))
    except (TypeError, ValueError, json.JSONDecodeError):
        return None
    return payload if isinstance(payload, dict) else None


def _parse_timestamp_value(value: object) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    text = str(value).strip()
    if not text:
        return None
    normalized = text.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        pass
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(text, fmt)
        except ValueError:
            continue
    return None


def _max_column_from_stats(
    stats_payloads: list[dict[str, Any] | None],
    column: str,
) -> tuple[datetime | None, bool]:
    if not stats_payloads:
        return None, True
    candidates: list[datetime] = []
    for stats in stats_payloads:
        if stats is None:
            return None, False
        max_values_payload = stats.get("maxValues")
        if not isinstance(max_values_payload, dict):
            return None, False
        if column not in max_values_payload:
            return None, False
        parsed = _parse_timestamp_value(max_values_payload[column])
        if parsed is None:
            return None, False
        candidates.append(parsed)
    if not candidates:
        return None, True
    return max(candidates), True
