"""Constants for the data observability monitoring layer (judged signals on profiling store)."""

from __future__ import annotations

SIGNAL_EMPTY_PARTITION = "empty_partition"
SIGNAL_STALE_DATA = "stale_data"

OBSERVABILITY_DATABASE = "datalake_observability"
PARTITION_METRICS_TABLE = "profile_partition_metrics"
TABLE_METRICS_TABLE = "profile_table_metrics"

UNKNOWN_OWNER = "unknown"
UNKNOWN_TEAM = "unknown"
UNKNOWN_PARTITION = "unknown"

DEFAULT_FRESHNESS_HOURS = 48
GCHAT_TEXT_MAX = 4096

DATALAKE_BUCKET_CONFIG = "datalake_bucket"
DATA_DOCUMENTATION_BUCKET_CONFIG = "data_documentation_bucket"

SLA_EXPECTATIONS_S3_PREFIX = "sla"
SLA_EXPECTATIONS_S3_KEY = f"{SLA_EXPECTATIONS_S3_PREFIX}/sla_expectations.json"

SLA_GLOB = "**/sla/**/*.yml"
