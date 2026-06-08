from __future__ import annotations

from pathlib import Path
from typing import Any, TypeAlias, cast

import yaml
from quintoandar_logger import QuintoAndarLogger

from scripts.jiraops.jiraops_enum import JiraOpsEnum
from scripts.jiraops.jiraops_task_criterion import (
    parse_task_criterion,
    routing_property_for_task,
)

logger = QuintoAndarLogger("BuildJiraOpsMuteCriteria")

JiraOpsMuteList: TypeAlias = dict[str, dict[str, list[str]]]
JiraOpsExceptionGovernance: TypeAlias = dict[str, Any]
JiraOpsRoutineExceptions: TypeAlias = dict[
    str, dict[str, dict[str, JiraOpsExceptionGovernance]]
]


class BuildJiraOpsMuteCriteria:
    """Build Jira Ops mute criteria (match-any-condition on extra-properties)."""

    def __init__(
        self,
        mute_list_path: Path | None = None,
        routine_exceptions_path: Path | None = None,
    ) -> None:
        self.mute_list_path = (
            mute_list_path or JiraOpsEnum.JIRA_OPS_MUTE_LIST_PATH.value
        )
        self.routine_exceptions_path = (
            routine_exceptions_path
            or JiraOpsEnum.JIRA_OPS_ROUTINE_EXCEPTIONS_PATH.value
        )
        self.jira_ops_extra_property_keys = (
            JiraOpsEnum.JIRA_OPS_EXTRA_PROPERTY_KEYS.value
        )
        self.dag_id_prefix = JiraOpsEnum.DAG_ID_PREFIX.value

    def load_jira_ops_mute_list(self) -> JiraOpsMuteList:
        if not self.mute_list_path.is_file():
            raise ValueError(f"Mute list not found: {self.mute_list_path}")

        with self.mute_list_path.open(encoding="utf-8") as stream:
            oncall_mute_list = yaml.safe_load(stream) or {}

        if not isinstance(oncall_mute_list, dict):
            raise ValueError(
                f"Jira Ops mute list must be a YAML mapping, got {type(oncall_mute_list).__name__}."
            )

        for key, operations in oncall_mute_list.items():
            if not isinstance(operations, dict):
                raise ValueError(
                    f"Value for key '{key}' must be a mapping, got {type(operations).__name__}."
                )
            for op, values in operations.items():
                if not isinstance(values, list):
                    raise ValueError(
                        f"Values for '{key}.{op}' must be a list, got {type(values).__name__}."
                    )

        unknown_keys = set(oncall_mute_list) - set(self.jira_ops_extra_property_keys)
        if unknown_keys:
            raise ValueError(
                f"Unknown Jira Ops mute list keys {sorted(unknown_keys)}. "
                f"Expected: {list(self.jira_ops_extra_property_keys)}."
            )

        return cast(JiraOpsMuteList, oncall_mute_list)

    def load_jira_ops_routine_exceptions(self) -> JiraOpsRoutineExceptions:
        if not self.routine_exceptions_path.is_file():
            raise ValueError(
                f"Routine exceptions not found: {self.routine_exceptions_path}"
            )

        with self.routine_exceptions_path.open(encoding="utf-8") as stream:
            routine_exceptions = yaml.safe_load(stream) or {}

        if not isinstance(routine_exceptions, dict):
            raise ValueError(
                f"Jira Ops routine exceptions must be a YAML mapping, got {type(routine_exceptions).__name__}."
            )

        for key, operations in routine_exceptions.items():
            if not isinstance(operations, dict):
                raise ValueError(
                    f"Value for key '{key}' must be a mapping, got {type(operations).__name__}."
                )
            for operation, entries in operations.items():
                if not isinstance(entries, dict):
                    raise ValueError(
                        f"Values for '{key}.{operation}' must be a mapping, "
                        f"got {type(entries).__name__}."
                    )

        unknown_keys = set(routine_exceptions) - set(self.jira_ops_extra_property_keys)
        if unknown_keys:
            raise ValueError(
                f"Unknown Jira Ops routine exceptions keys {sorted(unknown_keys)}. "
                f"Expected: {list(self.jira_ops_extra_property_keys)}."
            )

        return cast(JiraOpsRoutineExceptions, routine_exceptions)

    def _routing_entries_for_value(
        self, key: str, operation: str, value: str
    ) -> list[tuple[str, str]]:
        if key != "Task":
            return [(key, value)]
        parsed = parse_task_criterion(value, self.dag_id_prefix)
        routing_key, routing_value = routing_property_for_task(
            parsed, operation, self.dag_id_prefix
        )
        return [(routing_key, routing_value)]

    def build_routing_rule_criteria(self) -> dict[str, Any]:
        """Build Jira Ops routing rule criteria (match-any-condition on extra-properties)."""
        jira_ops_mute_list = self.load_jira_ops_mute_list()
        criteria: dict[str, Any] = {
            "type": "match-any-condition",
            "conditions": [],
        }
        order = 0
        for key in self.jira_ops_extra_property_keys:
            for operation, values in jira_ops_mute_list.get(key, {}).items():
                for value in values:
                    for routing_key, routing_value in self._routing_entries_for_value(
                        key, operation, value
                    ):
                        criteria["conditions"].append(
                            {
                                "field": "extra-properties",
                                "key": routing_key,
                                "not": False,
                                "operation": operation,
                                "expectedValue": routing_value,
                                "order": order,
                            }
                        )
                        order += 1
        return criteria
