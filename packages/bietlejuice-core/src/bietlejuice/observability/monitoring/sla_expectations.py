"""Load domain-owned SLA expectation files from the dags/ tree."""

from __future__ import annotations

import glob
import json
import logging
import os
from dataclasses import dataclass
from typing import Any, Literal, Union

import yaml

from bietlejuice.observability.monitoring.constants import SLA_GLOB

logger = logging.getLogger(__name__)

CHECK_EMPTY_PARTITION = "empty_partition"
CHECK_STALE_DATA = "stale_data"


@dataclass(frozen=True)
class EmptyPartitionCheck:
    type: Literal["empty_partition"] = CHECK_EMPTY_PARTITION


@dataclass(frozen=True)
class StaleDataCheck:
    column: str
    max_age_hours: int
    type: Literal["stale_data"] = CHECK_STALE_DATA


SlaCheck = Union[EmptyPartitionCheck, StaleDataCheck]


@dataclass(frozen=True)
class TableSla:
    checks: tuple[SlaCheck, ...]

    def has_empty_partition(self) -> bool:
        return any(check.type == CHECK_EMPTY_PARTITION for check in self.checks)

    def stale_data_checks(self) -> tuple[StaleDataCheck, ...]:
        return tuple(check for check in self.checks if check.type == CHECK_STALE_DATA)


def format_empty_partition_sla_brief() -> str:
    return "empty_partition opt-in"


def format_stale_data_sla_brief(check: StaleDataCheck) -> str:
    return f"stale_data on `{check.column}` within {check.max_age_hours}h"


def _optional_str(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _parse_check(entry: dict[str, Any], path: str) -> SlaCheck:
    check_type = entry.get("type")
    if check_type == CHECK_EMPTY_PARTITION:
        return EmptyPartitionCheck()
    if check_type == CHECK_STALE_DATA:
        column = _optional_str(entry.get("column"))
        if not column:
            raise ValueError(f"stale_data check missing column in {path}")
        max_age_hours = entry.get("max_age_hours")
        if max_age_hours is None:
            raise ValueError(f"stale_data check missing max_age_hours in {path}")
        try:
            max_age_hours_int = int(max_age_hours)
        except (TypeError, ValueError) as error:
            raise ValueError(
                f"stale_data max_age_hours must be a positive integer in {path}"
            ) from error
        if max_age_hours_int <= 0:
            raise ValueError(f"stale_data max_age_hours must be positive in {path}")
        return StaleDataCheck(column=column, max_age_hours=max_age_hours_int)
    raise ValueError(f"unknown SLA check type '{check_type}' in {path}")


def _parse_checks(raw_checks: object, path: str) -> tuple[SlaCheck, ...]:
    if raw_checks is None:
        raise ValueError(f"SLA file missing checks list: {path}")
    if not isinstance(raw_checks, list):
        raise ValueError(f"SLA checks must be a list in {path}")
    if not raw_checks:
        raise ValueError(f"SLA checks list is empty in {path}")
    seen_types: set[str] = set()
    parsed: list[SlaCheck] = []
    for entry in raw_checks:
        if not isinstance(entry, dict):
            raise ValueError(f"SLA check entry must be a mapping in {path}")
        check = _parse_check(entry, path)
        if check.type in seen_types:
            raise ValueError(f"duplicate SLA check type '{check.type}' in {path}")
        seen_types.add(check.type)
        parsed.append(check)
    return tuple(parsed)


def _check_to_dict(check: SlaCheck) -> dict[str, Any]:
    if isinstance(check, EmptyPartitionCheck):
        return {"type": CHECK_EMPTY_PARTITION}
    return {
        "type": CHECK_STALE_DATA,
        "column": check.column,
        "max_age_hours": check.max_age_hours,
    }


def _sla_to_dict(sla: TableSla) -> dict[str, Any]:
    return {"checks": [_check_to_dict(check) for check in sla.checks]}


def _sla_from_dict(payload: dict[str, Any]) -> TableSla:
    checks = payload.get("checks")
    if checks is None:
        raise ValueError("SLA payload missing checks")
    if not isinstance(checks, list):
        raise ValueError("SLA checks must be a list")
    parsed: list[SlaCheck] = []
    seen_types: set[str] = set()
    for entry in checks:
        if not isinstance(entry, dict):
            raise ValueError("SLA check entry must be a mapping")
        check = _parse_check(entry, "json")
        if check.type in seen_types:
            raise ValueError(f"duplicate SLA check type '{check.type}'")
        seen_types.add(check.type)
        parsed.append(check)
    return TableSla(checks=tuple(parsed))


def dump_expectations_json(
    expectations: dict[tuple[str, str], TableSla],
) -> str:
    """Serialize expectations for staging on S3 (EMR spark job input)."""
    payload = {
        f"{database}|{table}": _sla_to_dict(sla)
        for (database, table), sla in expectations.items()
    }
    return json.dumps(payload, sort_keys=True)


def load_expectations_from_json(text: str) -> dict[tuple[str, str], TableSla]:
    """Deserialize expectations staged for the EMR spark job."""
    raw = json.loads(text or "{}")
    if not isinstance(raw, dict):
        return {}
    expectations: dict[tuple[str, str], TableSla] = {}
    for key, value in raw.items():
        if not isinstance(key, str) or "|" not in key or not isinstance(value, dict):
            continue
        database, table = key.split("|", 1)
        try:
            expectations[(database, table)] = _sla_from_dict(value)
        except ValueError:
            logger.warning("Skipping invalid SLA JSON entry for %s", key)
    return expectations


def load_sla_expectations(dags_root: str) -> dict[tuple[str, str], TableSla]:
    """Glob ``dags/**/sla/**/*.yml`` and index by ``(database_name, table_name)``."""
    pattern = os.path.join(dags_root, SLA_GLOB)
    expectations: dict[tuple[str, str], TableSla] = {}
    for path in sorted(glob.glob(pattern, recursive=True)):
        try:
            with open(path, encoding="utf-8") as handle:
                content = yaml.safe_load(handle) or {}
            if not isinstance(content, dict):
                logger.warning("SLA file is not a mapping: %s", path)
                continue
            if "arrival" in content:
                raise ValueError(f"legacy arrival facet is no longer supported: {path}")
            database_name = content.get("database_name")
            table_name = content.get("table_name")
            if not database_name or not table_name:
                logger.warning("SLA file missing database_name/table_name: %s", path)
                continue
            checks = _parse_checks(content.get("checks"), path)
            key = (str(database_name).strip(), str(table_name).strip())
            expectations[key] = TableSla(checks=checks)
        except ValueError as error:
            logger.warning("Invalid SLA file %s: %s", path, error)
        except Exception:
            logger.warning("Failed to parse SLA file: %s", path, exc_info=True)
    return expectations
