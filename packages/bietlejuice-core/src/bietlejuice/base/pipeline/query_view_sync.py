from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Any


class QueryViewSyncTargetEnum(str, Enum):
    DATABRICKS = "databricks"
    TRINO = "trino"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]


class QueryViewSqlDialectEnum(str, Enum):
    DATABRICKS = "databricks"
    TRINO = "trino"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]


@dataclass(frozen=True)
class QueryViewSyncConfig:
    sync: tuple[str, ...]
    sql_dialect: str

    @property
    def has_trino_sync(self) -> bool:
        return QueryViewSyncTargetEnum.TRINO.value in self.sync


def normalize_query_view_sync_config(
    workflow_config: dict[str, Any],
    table_config: dict[str, Any] | None = None,
) -> QueryViewSyncConfig:
    """Resolve query_view sync targets and source SQL dialect."""
    table_config = table_config or {}
    if "has_hive_sync" in workflow_config or "has_hive_sync" in table_config:
        raise ValueError(
            "'has_hive_sync' is not supported for query_view. "
            "Use 'sync' and 'sql_dialect' instead."
        )

    sync_value = _get_overridden_value("sync", workflow_config, table_config)
    sql_dialect = _get_overridden_value(
        "sql_dialect",
        workflow_config,
        table_config,
        QueryViewSqlDialectEnum.DATABRICKS.value,
    )

    if sync_value is None:
        sync_value = (QueryViewSyncTargetEnum.DATABRICKS.value,)

    sync = _normalize_sync_targets(sync_value)
    sql_dialect = _normalize_sql_dialect(sql_dialect)

    return QueryViewSyncConfig(sync=sync, sql_dialect=sql_dialect)


def _get_overridden_value(
    key: str,
    workflow_config: dict[str, Any],
    table_config: dict[str, Any],
    default: Any = None,
) -> Any:
    if key in table_config and table_config[key] is not None:
        return table_config[key]
    value = workflow_config.get(key, default)
    if value is None:
        return default
    return value


def _normalize_sync_targets(value: Any) -> tuple[str, ...]:
    if isinstance(value, str):
        value = [value]

    if not isinstance(value, (list, tuple)) or len(value) == 0:
        raise ValueError("'sync' must be a non-empty list")

    allowed_targets = set(QueryViewSyncTargetEnum.get_available_enum_values())
    invalid_targets = [target for target in value if target not in allowed_targets]
    if invalid_targets:
        raise ValueError(
            "'sync' contains invalid targets. "
            f"Allowed values: {sorted(allowed_targets)}. "
            f"Invalid values: {invalid_targets}."
        )

    if len(set(value)) != len(value):
        raise ValueError("'sync' must not contain duplicate targets")

    target_set = set(value)
    return tuple(
        target.value for target in QueryViewSyncTargetEnum if target.value in target_set
    )


def _normalize_sql_dialect(value: Any) -> str:
    allowed_dialects = set(QueryViewSqlDialectEnum.get_available_enum_values())
    if value not in allowed_dialects:
        raise ValueError(
            f"'sql_dialect' must be one of {sorted(allowed_dialects)}. Got: {value}."
        )
    return value
