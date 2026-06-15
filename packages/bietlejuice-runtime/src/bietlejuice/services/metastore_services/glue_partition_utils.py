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
