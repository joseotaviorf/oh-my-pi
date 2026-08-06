"""Constants for the data observability monitoring layer (judged signals on profiling store)."""

from __future__ import annotations

SIGNAL_EMPTY_PARTITION = "empty_partition"

OBSERVABILITY_DATABASE = "datalake_observability"
PARTITION_METRICS_TABLE = "profile_partition_metrics"
TABLE_METRICS_TABLE = "profile_table_metrics"

UNKNOWN_OWNER = "unknown"
UNKNOWN_TEAM = "unknown"
UNKNOWN_PARTITION = "unknown"

DEFAULT_FRESHNESS_HOURS = 48
GCHAT_TEXT_MAX = 4096

DATALAKE_BUCKET_CONFIG = "datalake_bucket"

MONITORING_S3_PREFIX = "datalake_observability/monitoring"
SLA_EXPECTATIONS_S3_KEY = f"{MONITORING_S3_PREFIX}/sla_expectations.json"

DEFAULT_SLA_TIMEZONE = "America/Sao_Paulo"
SLA_GLOB = "**/sla/**/*.yml"

WEEKDAY_INDEX = {
    "mon": 0,
    "tue": 1,
    "wed": 2,
    "thu": 3,
    "fri": 4,
    "sat": 5,
    "sun": 6,
}

WEEKDAY_SUGAR: dict[str, set[int] | None] = {
    "all": None,
    "weekdays": {0, 1, 2, 3, 4},
}
