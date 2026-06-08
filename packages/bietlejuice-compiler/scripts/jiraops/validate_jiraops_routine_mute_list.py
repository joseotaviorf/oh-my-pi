"""CI entrypoint: validate jiraops_mute_list.yml (structure, duplicates, DAG/Task/DAGOwner)."""

from __future__ import annotations

import sys
from glob import glob
from os import scandir
from os.path import isdir, isfile, join

import yaml
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.enums.task_enum import TaskEnum
from dags import DAG_PACKAGES_ROOT
from scripts.dependency_handling.validate_dependencies_exist import (
    build_dependency_graph,
    dag_is_upstream_dependency_of_another_dag,
    read_dependencies_file,
    task_is_in_dependency_graph,
)
from scripts.jiraops.build_jiraops_mute_criteria import BuildJiraOpsMuteCriteria
from scripts.jiraops.jiraops_enum import JiraOpsEnum
from scripts.jiraops.jiraops_task_criterion import (
    parse_task_criterion,
    validate_task_contains,
    validate_task_equals,
)
from scripts.jiraops.validate_jiraops_routine_exceptions import (
    JiraOpsRoutineExceptionsValidator,
)

logger = QuintoAndarLogger("ValidateJiraOpsRoutineMuteList")


class JiraOpsRoutineMuteListValidator:
    """Validate jiraops_mute_list.yml (structure, duplicates, DAG/Task/DAGOwner)."""

    def __init__(self) -> None:
        self.mute_list_path = JiraOpsEnum.JIRA_OPS_MUTE_LIST_PATH.value
        self.dag_names = self._collect_dag_names()
        self.valid_owners = set(DAGOwnerEnum.get_available_enum_values())
        self.routine_exceptions_validator = JiraOpsRoutineExceptionsValidator()

        self.errors: list[str] = []

        self.expected_extra_property_keys = (
            JiraOpsEnum.JIRA_OPS_EXTRA_PROPERTY_KEYS.value
        )
        self.allowed_operations = JiraOpsEnum.ALLOWED_OPERATIONS.value
        self.contains_suffixes = JiraOpsEnum.CONTAINS_SUFFIXES.value
        self.dag_id_prefix = JiraOpsEnum.DAG_ID_PREFIX.value
        self.routine_exceptions_path = (
            JiraOpsEnum.JIRA_OPS_ROUTINE_EXCEPTIONS_PATH.value.name
        )
        self.task_name_pattern = JiraOpsEnum._TASK_NAME_PATTERN.value
        self.built_task_prefixes = JiraOpsEnum._BUILT_TASK_PREFIXES.value

    def _load_dependency_context(self) -> None:
        dependencies = read_dependencies_file()
        self.dependency_graph = build_dependency_graph(dependencies)
        self.dag_owners = JiraOpsRoutineExceptionsValidator.collect_dag_owners()
        self.task_upstream_dags = (
            JiraOpsRoutineExceptionsValidator.build_task_upstream_dags(
                dependencies, self.dag_id_prefix
            )
        )

    def validate_mute_list(self) -> list[str]:
        self.errors = []
        try:
            self.mute_list = BuildJiraOpsMuteCriteria().load_jira_ops_mute_list()
        except Exception as err:
            logger.error(f"Failed to load Jira Ops mute list: {err}")
            return [str(err)]

        self._load_dependency_context()

        self.errors.extend(
            self.routine_exceptions_validator.validate_routine_exceptions()
        )
        self.errors.extend(self._check_keys(self.mute_list))
        self.errors.extend(self._check_duplicates(self.mute_list))
        self.errors.extend(
            self.routine_exceptions_validator.check_dag_owners_require_exception(
                self.mute_list
            )
        )

        for key in self.mute_list.keys():
            for operation, values in self.mute_list.get(key, {}).items():
                for value in values:
                    if key != "DAGOwner":
                        if self._is_valid_value(key, operation, value):
                            if self._check_expected_value_exists(key, operation, value):
                                self._check_dependencies(key, operation, value)
                    elif key == "DAGOwner" and operation == "equals":
                        if value not in self.valid_owners:
                            self.errors.append(
                                f"{key}-{operation}]: {value!r} is not a DAGOwnerEnum value."
                            )
                    elif key == "DAGOwner" and operation != "equals":
                        self.errors.append(
                            f"{key}-{operation}]: operation {operation!r} is not supported for DAG owners."
                        )

        self.errors.extend(
            self.routine_exceptions_validator.check_criteria_redundant_with_muted_owners(
                self.mute_list,
                self.dag_owners,
                self.dag_names,
                self.dag_id_prefix,
                self.task_upstream_dags,
            )
        )

        return self.errors

    def _check_expected_value_exists(
        self, key: str, operation: str, value: str
    ) -> bool:
        if key == "DAG":
            return self._check_dag_name_pattern(operation, value)
        elif key == "Task":
            return self._check_task_criterion(operation, value)
        return False

    def _check_dag_name_pattern(self, operation: str, dag_name: str) -> bool:
        dag_name = self._dag_name_from_dag_id(dag_name)

        if operation == "equals" and dag_name not in self.dag_names:
            self.errors.append(
                f"DAG[{operation}]: {dag_name!r} not found in dags/ "
                "(expected *_declaration.yml, {{name}}.py, {{name}}_dag.py or {{name}}.yml)."
            )
            return False
        elif operation == "contains" and not any(
            name.startswith(dag_name) for name in self.dag_names
        ):
            self.errors.append(
                f"DAG[{operation}]: prefix {dag_name!r} not found in dags/ "
                "(no dag.name starts with this value)."
            )
            return False
        else:
            return True

    def _check_task_criterion(self, operation: str, value: str) -> bool:
        if operation == "contains":
            task_errors = validate_task_contains(
                value,
                dag_id_prefix=self.dag_id_prefix,
                dag_names=self.dag_names,
                task_name_pattern=self.task_name_pattern,
                task_enum_values=self._task_enum_values(),
                built_task_prefixes=self.built_task_prefixes,
            )
            self.errors.extend(task_errors)
            return not task_errors

        task_errors = validate_task_equals(
            value,
            dag_names=self.dag_names,
            dag_id_prefix=self.dag_id_prefix,
            task_name_pattern=self.task_name_pattern,
            task_enum_values=self._task_enum_values(),
            built_task_prefixes=self.built_task_prefixes,
        )
        self.errors.extend(task_errors)
        return not task_errors

    def _check_dependencies(self, key: str, operation: str, value: str) -> None:
        if key == "DAG" and operation == "equals":
            if dag_is_upstream_dependency_of_another_dag(
                value, self.dependency_graph
            ) and not self.routine_exceptions_validator._has_special_exception(
                key, operation, value
            ):
                self.errors.append(
                    f"{key}[{operation}]: {value!r} is listed in dags/dependencies.yaml "
                    "(dependent DAG or upstream dependency); cannot mute."
                )
        elif key == "DAG" and operation == "contains":
            name_prefix = self._dag_name_from_dag_id(value)
            matching_dags = [
                dag_name
                for dag_name in self.dag_names
                if dag_name.startswith(name_prefix)
            ]
            has_upstream_match = any(
                dag_is_upstream_dependency_of_another_dag(
                    f"{self.dag_id_prefix}{dag_name}", self.dependency_graph
                )
                for dag_name in matching_dags
            )
            if (
                has_upstream_match
                and not self.routine_exceptions_validator._has_special_exception(
                    key, operation, value
                )
            ):
                self.errors.append(
                    f"{key}[{operation}]: prefix {value!r} matches DAG(s) that are "
                    "upstream dependencies in dags/dependencies.yaml; cannot mute."
                )
        elif key == "Task":
            parsed = parse_task_criterion(value, self.dag_id_prefix)
            if task_is_in_dependency_graph(
                parsed.task_id, self.dependency_graph
            ) and not self.routine_exceptions_validator._has_special_exception(
                key, operation, value
            ):
                self.errors.append(
                    f"Task[{operation}]: {value!r} is an upstream task dependency of another "
                    "DAG in dags/dependencies.yaml; cannot mute."
                )

    def _is_valid_value(self, key: str, operation: str, value: str) -> bool:
        if operation == "equals" and not bool(value.strip()):
            self.errors.append(f"{key}[{operation}]: {value!r} is empty.")
            return False
        elif operation == "contains" and not bool(value.strip()):
            self.errors.append(f"{key}[{operation}]: {value!r} is empty.")
            return False
        elif (
            operation == "contains"
            and key == "DAG"
            and not value.strip().endswith(self.contains_suffixes)
        ):
            self.errors.append(
                f"{key}[{operation}]: {value!r} must end with '_' or '-' "
                "(e.g. bietlejuice.qube_, optimize-)."
            )
            return False
        return True

    def _dag_name_from_dag_id(self, dag_id: str) -> str:
        return dag_id.removeprefix(self.dag_id_prefix)

    def _check_keys(self, mute_list: dict) -> list[str]:
        errors: list[str] = []
        unknown = set(mute_list) - set(self.expected_extra_property_keys)
        if unknown:
            errors.append(
                f"Unknown keys {sorted(unknown)}. "
                f"Expected extra-properties keys: {list(self.expected_extra_property_keys)}."
            )

        for key in self.expected_extra_property_keys:
            operations = mute_list.get(key)
            if operations is None:
                continue
            if not isinstance(operations, dict):
                errors.append(
                    f"Key {key!r} must be a dictionary of operations and lists of strings."
                )
                continue
            for operation, values in operations.items():
                if operation not in self.allowed_operations:
                    errors.append(
                        f"{key}: unknown operation {operation!r}. "
                        f"Allowed: {sorted(self.allowed_operations)}."
                    )
                    continue
                if not isinstance(values, list):
                    errors.append(f"{key}[{operation}]: must be a list of strings.")
                    continue
                for index, value in enumerate(values):
                    if not isinstance(value, str):
                        errors.append(f"{key}[{operation}][{index}]: must be a string.")
                    elif not value.strip():
                        errors.append(
                            f"{key}[{operation}][{index}]: empty value is not allowed."
                        )

        return errors

    def _check_duplicates(self, mute_list: dict) -> list[str]:
        errors: list[str] = []
        seen: dict[str, str] = {}
        for key in self.expected_extra_property_keys:
            for operation, values in mute_list.get(key, {}).items():
                for index, value in enumerate(values):
                    if not isinstance(value, str):
                        continue
                    normalized = value.strip()
                    if not normalized:
                        continue
                    label = f"{key}-{operation}]"
                    if normalized in seen:
                        errors.append(
                            f"{label}: duplicate criterion {normalized!r}"
                            f"(already in {seen[normalized]})."
                        )
                    else:
                        seen[normalized] = label
        return errors

    @staticmethod
    def _collect_dag_names() -> set[str]:
        """DAG names from *_declaration.yml and Python/metric packages ({name}.py, {name}_dag.py, {name}.yml)."""
        dag_names: set[str] = set()

        for declaration_path in glob(
            f"{DAG_PACKAGES_ROOT}/**/*_declaration.yml", recursive=True
        ):
            try:
                with open(declaration_path, encoding="utf-8") as stream:
                    declaration = yaml.safe_load(stream) or {}
                name = (declaration.get("dag") or {}).get("name")
                if name:
                    dag_names.add(name)
            except (OSError, yaml.YAMLError, TypeError, AttributeError) as e:
                logger.warning(
                    f"Skipping malformed declaration file {declaration_path}: {e}"
                )

        if not DAG_PACKAGES_ROOT or not isdir(DAG_PACKAGES_ROOT):
            return dag_names

        for line_entry in scandir(DAG_PACKAGES_ROOT):
            if not line_entry.is_dir() or line_entry.name.startswith("."):
                continue
            for dag_entry in scandir(line_entry.path):
                if not dag_entry.is_dir() or dag_entry.name.startswith("."):
                    continue
                dag_name = dag_entry.name
                dag_path = dag_entry.path
                if any(
                    isfile(join(dag_path, filename))
                    for filename in (
                        f"{dag_name}.py",
                        f"{dag_name}_dag.py",
                        f"{dag_name}.yml",
                    )
                ):
                    dag_names.add(dag_name)

        return dag_names

    @staticmethod
    def _task_enum_values() -> set[str]:
        values = {member.value for member in TaskEnum}
        values |= {value.replace("_", "-") for value in values}
        return values


def main() -> int:
    validator = JiraOpsRoutineMuteListValidator()
    errors = validator.validate_mute_list()

    if errors:
        for error in errors:
            logger.error(error)
        logger.error(
            "Validation failed with %s error(s) in %s",
            len(errors),
            validator.mute_list_path,
        )
        return 1

    logger.info("Valid jiraops_mute_list.yml! 🎉")
    return 0


if __name__ == "__main__":
    sys.exit(main())
