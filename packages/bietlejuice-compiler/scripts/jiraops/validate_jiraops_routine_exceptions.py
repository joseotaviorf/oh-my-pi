"""Validate jiraops_mute_list_exceptions.yml governance fields."""

from __future__ import annotations

import sys
from datetime import datetime
from glob import glob
from pathlib import Path

import yaml
from quintoandar_logger import QuintoAndarLogger

from dags import DAG_PACKAGES_ROOT
from scripts.jiraops.build_jiraops_mute_criteria import (
    BuildJiraOpsMuteCriteria,
    JiraOpsRoutineExceptions,
)
from scripts.jiraops.jiraops_enum import JiraOpsEnum
from scripts.jiraops.jiraops_task_criterion import parse_task_criterion

logger = QuintoAndarLogger("ValidateJiraOpsRoutineExceptions")


class JiraOpsRoutineExceptionsValidator:
    """Validate jiraops_mute_list_exceptions.yml (governance per criterion)."""

    def __init__(
        self,
        routine_exceptions: JiraOpsRoutineExceptions | None = None,
        routine_exceptions_path: Path | None = None,
    ) -> None:
        self.expected_extra_property_keys = (
            JiraOpsEnum.JIRA_OPS_EXTRA_PROPERTY_KEYS.value
        )
        self.required_exception_fields = JiraOpsEnum.REQUIRED_EXCEPTION_FIELDS.value
        self.deadline_date_pattern = JiraOpsEnum.DEADLINE_DATE_PATTERN.value
        self.deadline_never = JiraOpsEnum.DEADLINE_NEVER.value
        self.allowed_operations = JiraOpsEnum.ALLOWED_OPERATIONS.value
        path = (
            routine_exceptions_path
            or JiraOpsEnum.JIRA_OPS_ROUTINE_EXCEPTIONS_PATH.value
        )
        self.routine_exceptions_path = path
        self.routine_exceptions_file_name = path.name

        if routine_exceptions is not None:
            self.routine_exceptions = routine_exceptions
        else:
            self.routine_exceptions = BuildJiraOpsMuteCriteria(
                routine_exceptions_path=path
            ).load_jira_ops_routine_exceptions()

    def validate_routine_exceptions(self) -> list[str]:
        errors: list[str] = []
        label_prefix = self.routine_exceptions_file_name

        unknown_keys = set(self.routine_exceptions) - set(
            self.expected_extra_property_keys
        )
        if unknown_keys:
            errors.append(
                f"{label_prefix}: unknown keys {sorted(unknown_keys)}. "
                f"Expected: {list(self.expected_extra_property_keys)}."
            )

        for key in self.expected_extra_property_keys:
            operations = self.routine_exceptions.get(key)
            if operations is None:
                continue
            if not isinstance(operations, dict):
                errors.append(
                    f"{label_prefix}: key {key!r} must be a mapping of "
                    "operations to criterion entries."
                )
                continue

            for operation, entries in operations.items():
                label = f"{label_prefix}[{key}][{operation}]"
                if operation not in self.allowed_operations:
                    errors.append(
                        f"{label}: unknown operation {operation!r}. "
                        f"Allowed: {sorted(self.allowed_operations)}."
                    )
                    continue
                if not isinstance(entries, dict):
                    errors.append(
                        f"{label}: must be a mapping of criterion values to governance fields."
                    )
                    continue

                for criterion, governance in entries.items():
                    entry_label = f"{label}[{criterion!r}]"
                    if not isinstance(criterion, str) or not criterion.strip():
                        errors.append(
                            f"{entry_label}: criterion key must be a non-empty string."
                        )
                        continue
                    if not isinstance(governance, dict):
                        errors.append(
                            f"{entry_label}: must be a mapping with "
                            f"{sorted(self.required_exception_fields)}."
                        )
                        continue

                    errors.extend(
                        self._validate_exception_governance_fields(
                            entry_label, governance
                        )
                    )

        return errors

    def _validate_exception_governance_fields(
        self, entry_label: str, governance: dict
    ) -> list[str]:
        errors: list[str] = []
        for field in self.required_exception_fields:
            value = governance.get(field)
            if value is None or not str(value).strip():
                errors.append(f"{entry_label}: missing required field {field!r}.")

        deadline = governance.get("deadline")
        if deadline is not None and str(deadline).strip():
            deadline_text = str(deadline).strip()
            if deadline_text != self.deadline_never:
                if not self.deadline_date_pattern.match(deadline_text):
                    errors.append(
                        f"{entry_label}: deadline {deadline_text!r} must be "
                        f"{self.deadline_never!r} or a date YYYY-MM-DD."
                    )
                else:
                    try:
                        datetime.strptime(deadline_text, "%Y-%m-%d")
                    except ValueError:
                        errors.append(
                            f"{entry_label}: deadline {deadline_text!r} is not a valid date."
                        )
        return errors

    def _has_special_exception(self, key: str, operation: str, value: str) -> bool:
        return value in self.routine_exceptions.get(key, {}).get(operation, {})

    def check_dag_owners_require_exception(self, mute_list: dict) -> list[str]:
        errors: list[str] = []
        for owner in mute_list.get("DAGOwner", {}).get("equals", []):
            if not isinstance(owner, str):
                continue
            owner = owner.strip()
            if not owner:
                continue
            if not self._has_special_exception("DAGOwner", "equals", owner):
                errors.append(
                    f"DAGOwner[equals]: {owner!r} requires a documented entry in "
                    f"{self.routine_exceptions_file_name} "
                    f"(fields: {sorted(self.required_exception_fields)})."
                )
        return errors

    @staticmethod
    def collect_dag_owners() -> dict[str, str]:
        """dag.name -> dag.owner from *_declaration.yml (same scope as mute-list DAG checks)."""
        dag_owners: dict[str, str] = {}
        for declaration_path in glob(
            f"{DAG_PACKAGES_ROOT}/**/*_declaration.yml", recursive=True
        ):
            try:
                with open(declaration_path, encoding="utf-8") as stream:
                    declaration = yaml.safe_load(stream) or {}
                dag_block = declaration.get("dag") or {}
                name = dag_block.get("name")
                owner = dag_block.get("owner")
                if name and owner:
                    dag_owners[str(name)] = str(owner)
            except (OSError, yaml.YAMLError, TypeError, AttributeError) as e:
                logger.warning(
                    "Could not parse DAG declaration %s: %s", declaration_path, e
                )
        return dag_owners

    @staticmethod
    def build_task_upstream_dags(
        dependencies: dict, dag_id_prefix: str
    ) -> dict[str, set[str]]:
        """Task id -> upstream DAG short names from dag:task entries in dependencies.yaml."""
        task_dags: dict[str, set[str]] = {}
        for dependency_list in dependencies.values():
            for dependency in dependency_list or []:
                if not isinstance(dependency, str) or ":" not in dependency:
                    continue
                dag_id, task_id, *_ = dependency.split(":")
                short_name = dag_id.removeprefix(dag_id_prefix)
                task_dags.setdefault(task_id, set()).add(short_name)
        return task_dags

    def check_criteria_redundant_with_muted_owners(
        self,
        mute_list: dict,
        dag_owners: dict[str, str],
        dag_names: set[str],
        dag_id_prefix: str,
        task_upstream_dags: dict[str, set[str]] | None = None,
    ) -> list[str]:
        """DAG/Task criteria are redundant when DAGOwner[equals] already mutes that owner."""
        errors: list[str] = []
        muted_owners = {
            owner.strip()
            for owner in mute_list.get("DAGOwner", {}).get("equals", [])
            if isinstance(owner, str) and owner.strip()
        }
        if not muted_owners:
            return errors

        for dag_id in mute_list.get("DAG", {}).get("equals", []):
            if not isinstance(dag_id, str):
                continue
            short_name = dag_id.removeprefix(dag_id_prefix)
            owner = dag_owners.get(short_name)
            if owner and owner in muted_owners:
                errors.append(
                    f"DAG[equals]: {dag_id!r} is redundant; DAG owner {owner!r} is "
                    "already muted via DAGOwner[equals]."
                )

        for prefix in mute_list.get("DAG", {}).get("contains", []):
            if not isinstance(prefix, str):
                continue
            name_prefix = prefix.removeprefix(dag_id_prefix)
            matching = [name for name in dag_names if name.startswith(name_prefix)]
            if not matching:
                continue
            owners_for_match = {dag_owners.get(name) for name in matching}
            if None in owners_for_match:
                continue
            if owners_for_match <= muted_owners:
                errors.append(
                    f"DAG[contains]: prefix {prefix!r} is redundant; all matching DAGs "
                    f"belong to owners already muted via DAGOwner[equals]: "
                    f"{sorted(owners_for_match)}."
                )

        muted_dag_ids = {
            dag_id.strip()
            for dag_id in mute_list.get("DAG", {}).get("equals", [])
            if isinstance(dag_id, str) and dag_id.strip()
        }

        for task_entry in mute_list.get("Task", {}).get("equals", []):
            if not isinstance(task_entry, str):
                continue
            parsed = parse_task_criterion(task_entry, dag_id_prefix)
            if parsed.is_global:
                continue
            if parsed.dag_id and parsed.dag_id in muted_dag_ids:
                errors.append(
                    f"Task[equals]: {task_entry!r} is redundant; DAG {parsed.dag_id!r} is "
                    "already muted via DAG[equals]."
                )
                continue
            if parsed.dag_id:
                short_name = parsed.dag_id.removeprefix(dag_id_prefix)
                owner = dag_owners.get(short_name)
                if owner and owner in muted_owners:
                    errors.append(
                        f"Task[equals]: {task_entry!r} is redundant; DAG owner {owner!r} is "
                        "already muted via DAGOwner[equals]."
                    )
                continue
            if not task_upstream_dags:
                continue
            upstream_dags = task_upstream_dags.get(parsed.task_id)
            if not upstream_dags:
                continue
            owners_for_task = {dag_owners.get(name) for name in upstream_dags}
            if None in owners_for_task:
                continue
            if owners_for_task <= muted_owners:
                errors.append(
                    f"Task[equals]: {task_entry!r} is redundant; upstream DAG(s) in "
                    "dependencies.yaml belong only to owners already muted via "
                    f"DAGOwner[equals]: {sorted(owners_for_task)}."
                )

        return errors


def main() -> int:
    validator = JiraOpsRoutineExceptionsValidator()
    errors = validator.validate_routine_exceptions()

    if errors:
        for error in errors:
            logger.error(error)
        logger.error(
            "Validation failed with %s error(s) in %s",
            len(errors),
            validator.routine_exceptions_file_name,
        )
        return 1

    logger.info("Valid %s 🎉", validator.routine_exceptions_file_name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
