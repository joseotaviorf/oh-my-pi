"""
Pure helpers for AWS Glue hive-style partition registration.

Kept separate from ``glue_metastore_service`` so partition logic can be
unit-tested without boto3/Glue clients and without importing Spark.
"""

from __future__ import annotations

from copy import deepcopy
from datetime import date, datetime
from typing import Dict, Iterable, List, Sequence, Tuple

import boto3


def format_partition_value(value) -> str:
    """Stringify a partition column value for Glue ``Values`` and S3 paths."""
    if isinstance(value, datetime):
        return value.isoformat(sep=" ", timespec="seconds")
    if isinstance(value, date):
        return value.isoformat()
    return str(value)


def normalise_s3_location(location: str) -> str:
    """Ensure the S3 location uses the ``s3://`` scheme."""
    if location.startswith("s3a://"):
        return location.replace("s3a://", "s3://", 1)
    if location.startswith("s3n://"):
        return location.replace("s3n://", "s3://", 1)
    return location


def ensure_trailing_slash(location: str) -> str:
    return location if location.endswith("/") else f"{location}/"


def build_hive_partition_path(
    table_location: str,
    partition_key_names: Sequence[str],
    partition_values: Dict,
) -> str:
    """Build ``s3://bucket/table/year=2026/month=06/day=12/`` from key order."""
    base = ensure_trailing_slash(normalise_s3_location(table_location))
    segments = [
        f"{key}={format_partition_value(partition_values[key])}"
        for key in partition_key_names
    ]
    return base + "/".join(segments) + "/"


def partition_values_tuple(
    partition_key_names: Sequence[str], partition_values: Dict
) -> Tuple[str, ...]:
    return tuple(
        format_partition_value(partition_values[key]) for key in partition_key_names
    )


def copy_storage_descriptor_for_partition(
    table_storage_descriptor: Dict, partition_location: str
) -> Dict:
    """Clone a table ``StorageDescriptor`` with a partition-specific location."""
    sd = deepcopy(table_storage_descriptor)
    sd["Location"] = ensure_trailing_slash(normalise_s3_location(partition_location))
    sd.setdefault("Compressed", False)
    sd.setdefault("StoredAsSubDirectories", False)
    return sd


def build_partition_input(
    table_storage_descriptor: Dict,
    partition_key_names: Sequence[str],
    partition_values: Dict,
    table_location: str,
) -> Dict:
    """Build a Glue ``PartitionInput`` dict."""
    location = build_hive_partition_path(
        table_location, partition_key_names, partition_values
    )
    return {
        "Values": list(partition_values_tuple(partition_key_names, partition_values)),
        "StorageDescriptor": copy_storage_descriptor_for_partition(
            table_storage_descriptor, location
        ),
    }


def is_delta_glue_table(table: Dict) -> bool:
    """Return True when Glue table metadata represents Delta (no hive partitions)."""
    params = table.get("Parameters") or {}
    if params.get("spark.sql.sources.provider") == "delta":
        return True
    if params.get("classification") == "delta":
        return True
    return False


# Both SerDes appear in the catalog: OpenX is the current registration, HCatalog
# survives on tables not re-registered since #27258.
_JSON_SERDE_HCATALOG = "org.apache.hive.hcatalog.data.JsonSerDe"
_JSON_SERDE_OPENX = "org.openx.data.jsonserde.JsonSerDe"


def _serde_library(storage_descriptor: Dict) -> str:
    serde = (storage_descriptor or {}).get("SerdeInfo") or {}
    return serde.get("SerializationLibrary") or ""


def is_json_glue_table(table: Dict) -> bool:
    """Return True when the Glue table is JSON (classification or JsonSerDe)."""
    params = table.get("Parameters") or {}
    if (params.get("classification") or "").lower() == "json":
        return True
    serde = _serde_library(table.get("StorageDescriptor") or {})
    return serde in (_JSON_SERDE_HCATALOG, _JSON_SERDE_OPENX)


def _column_signature(storage_descriptor: Dict) -> List[Tuple[str, str]]:
    """Ordered ``(name, type)`` pairs, case-folded, for drift comparison.

    Order is significant: Glue column order is positional metadata for the Hive
    reader, so a reordered partition is as broken as a retyped one.
    """
    return [
        (
            str(column.get("Name", "")).lower(),
            str(column.get("Type", "")).strip().lower(),
        )
        for column in ((storage_descriptor or {}).get("Columns") or [])
    ]


def partition_serde_needs_update(
    table_storage_descriptor: Dict, partition_storage_descriptor: Dict
) -> bool:
    """True when partition SerDe or columns differ from the table.

    Partitions carry their own ``SerdeInfo`` *and* ``Columns``, and Spark builds
    the deserializer from the partition descriptor, so a table whose column
    types were coerced (``decimal`` -> ``string``) still reads through the old
    partition types until the partitions are updated too.
    """
    table_serde = (table_storage_descriptor or {}).get("SerdeInfo") or {}
    part_serde = (partition_storage_descriptor or {}).get("SerdeInfo") or {}
    if table_serde.get("SerializationLibrary") != part_serde.get(
        "SerializationLibrary"
    ):
        return True
    if (table_serde.get("Parameters") or {}) != (part_serde.get("Parameters") or {}):
        return True
    return _column_signature(table_storage_descriptor) != _column_signature(
        partition_storage_descriptor
    )


def build_partition_update_entry(
    table_storage_descriptor: Dict, partition: Dict
) -> Dict:
    """Build a Glue ``BatchUpdatePartition`` entry; keep Values + Location."""
    values = list(partition.get("Values") or [])
    partition_sd = partition.get("StorageDescriptor") or {}
    location = partition_sd.get("Location") or ""
    return {
        "PartitionValueList": values,
        "PartitionInput": {
            "Values": values,
            "StorageDescriptor": copy_storage_descriptor_for_partition(
                table_storage_descriptor, location
            ),
            "Parameters": dict(partition.get("Parameters") or {}),
        },
    }


def merge_glue_columns(
    existing_columns: Sequence[Dict] | None,
    incoming_columns: Sequence[Dict] | None,
) -> Tuple[List[Dict], List[str]]:
    """Union two Glue column lists so a re-registration can never drop a column.

    Glue's ``update_table`` replaces ``StorageDescriptor.Columns`` wholesale,
    while the Spark/UC side issues ``CREATE TABLE IF NOT EXISTS`` and is a no-op
    on an existing table.  A run whose source payload omitted an optional field
    therefore narrows the Glue table while UC keeps its accumulated union, and
    the Hive JSON reader on EMR then rejects the column as non-existent.
    Merging closes that gap.

    Existing column order is preserved (Glue column order is positional metadata
    for the reader); columns new to this run are appended.  On a name collision
    the incoming ``Type`` wins — this run has fresher type information — while
    extra keys already on the existing column (``Comment``, ``Parameters``)
    survive.  Names are matched case-insensitively, as in ``_split_columns``,
    because Glue lower-cases column names.

    :return: ``(merged_columns, preserved_names)`` where ``preserved_names``
        lists the columns kept only because the existing table had them.  A
        non-empty list means the incoming schema was narrower.
    """
    existing = list(existing_columns or [])
    incoming = list(incoming_columns or [])

    incoming_by_name = {
        str(col.get("Name", "")).lower(): col for col in incoming if col.get("Name")
    }

    merged: List[Dict] = []
    preserved: List[str] = []

    for column in existing:
        name = str(column.get("Name", "")).lower()
        match = incoming_by_name.get(name) if name else None
        if match is None:
            merged.append(dict(column))
            if name:
                preserved.append(column["Name"])
            continue
        combined = dict(column)
        combined.update(match)
        # Keep the registered spelling so a case-only difference is not churn.
        combined["Name"] = column.get("Name", match.get("Name"))
        merged.append(combined)

    existing_names = {
        str(col.get("Name", "")).lower() for col in existing if col.get("Name")
    }
    for column in incoming:
        name = str(column.get("Name", "")).lower()
        if not name or name not in existing_names:
            merged.append(dict(column))

    return merged, preserved


def discover_hive_partitions_from_s3(
    table_location: str,
    partition_key_names: Sequence[str],
    *,
    s3_client=None,
) -> List[Tuple[str, ...]]:
    """Walk hive-style S3 prefixes and return partition value tuples.

    Discovers folders such as ``year=2026/month=06/day=12/`` under
    ``table_location``.  Only prefixes whose depth matches
    ``len(partition_key_names)`` are returned.

    **Performance:** intended for one-off backfill (``repair_table_partitions`` /
    ``sync_glue_partitions``), not per-DAG writes.  Cost grows with partition
    cardinality: one ``ListObjectsV2`` call per ``year`` / ``year/month`` node,
    which is fine for ``year/month/day`` calendar tables but expensive when an
    early partition key has very high cardinality (e.g. ``sync_id``).

    Pass ``s3_client`` from ``GlueClient.get_s3_client()`` so S3 listing uses
    the same STS credentials as Glue (``GLUE_ASSUME_ROLE_ARN``).
    """
    if not partition_key_names:
        return []

    location = ensure_trailing_slash(normalise_s3_location(table_location))
    if not location.startswith("s3://"):
        raise ValueError(
            f"discover_hive_partitions_from_s3: expected s3 location, got {location!r}"
        )

    bucket, prefix = _split_s3_uri(location)
    client = s3_client or boto3.client("s3")
    return _discover_prefixes(
        client, bucket, prefix, list(partition_key_names), depth=0
    )


def _split_s3_uri(uri: str) -> Tuple[str, str]:
    without_scheme = uri[5:]
    bucket, _, key = without_scheme.partition("/")
    return bucket, key


def _discover_prefixes(
    s3_client,
    bucket: str,
    prefix: str,
    partition_key_names: List[str],
    depth: int,
    accumulated: Tuple[str, ...] = (),
) -> List[Tuple[str, ...]]:
    if depth >= len(partition_key_names):
        return [accumulated] if accumulated else []

    expected_key = partition_key_names[depth]
    paginator = s3_client.get_paginator("list_objects_v2")
    value_tuples: List[Tuple[str, ...]] = []

    for page in paginator.paginate(Bucket=bucket, Prefix=prefix, Delimiter="/"):
        for common_prefix in page.get("CommonPrefixes", []):
            child_prefix = common_prefix.get("Prefix", "")
            segment = child_prefix[len(prefix) :].strip("/")
            if "=" not in segment:
                continue
            key_name, _, raw_value = segment.partition("=")
            if key_name != expected_key:
                continue

            child_accumulated = accumulated + (raw_value,)
            if depth + 1 == len(partition_key_names):
                value_tuples.append(child_accumulated)
            else:
                value_tuples.extend(
                    _discover_prefixes(
                        s3_client,
                        bucket,
                        child_prefix,
                        partition_key_names,
                        depth + 1,
                        child_accumulated,
                    )
                )

    return value_tuples


def partition_tuples_to_dicts(
    partition_key_names: Sequence[str],
    value_tuples: Iterable[Tuple[str, ...]],
) -> List[Dict[str, str]]:
    """Convert discovered tuples into partition dicts keyed by column name."""
    result: List[Dict[str, str]] = []
    for values in value_tuples:
        if len(values) != len(partition_key_names):
            continue
        result.append(dict(zip(partition_key_names, values)))
    return result
