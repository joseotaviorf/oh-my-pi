"""Parse and route Task mute-list entries (YAML) to Jira Ops extra-properties."""

from __future__ import annotations

from dataclasses import dataclass

from scripts.jiraops.jiraops_enum import JiraOpsEnum


@dataclass(frozen=True)
class ParsedTaskCriterion:
    raw: str
    dag_id: str | None
    task_id: str
    is_global: bool


def parse_task_criterion(
    value: str, dag_id_prefix: str = JiraOpsEnum.DAG_ID_PREFIX.value
) -> ParsedTaskCriterion:
    value = value.strip()
    global_dag = f"{dag_id_prefix}*"
    if ":" not in value:
        return ParsedTaskCriterion(
            raw=value, dag_id=None, task_id=value, is_global=False
        )
    dag_part, task_id = value.split(":", 1)
    dag_part = dag_part.strip()
    task_id = task_id.strip()
    is_global = dag_part == global_dag
    return ParsedTaskCriterion(
        raw=value,
        dag_id=dag_part,
        task_id=task_id,
        is_global=is_global,
    )


def is_pipeline_task(task_id: str) -> bool:
    return task_id.startswith(JiraOpsEnum.FORBIDDEN_PIPELINE_TASK_PREFIXES.value)


def is_general_task(task_id: str) -> bool:
    return task_id in JiraOpsEnum.GENERAL_TASK_IDS.value


def routing_property_for_task(
    parsed: ParsedTaskCriterion,
    operation: str,
    dag_id_prefix: str = JiraOpsEnum.DAG_ID_PREFIX.value,
) -> tuple[str, str]:
    """Map YAML Task entry to Jira routing extra-property key and expectedValue."""
    if operation == "contains":
        if parsed.is_global:
            return "Task", parsed.task_id
        if parsed.dag_id:
            return "TaskPath", f"{parsed.dag_id}:{parsed.task_id}"
        return "Task", parsed.raw

    if parsed.is_global:
        return "Task", parsed.task_id
    if parsed.dag_id:
        return "TaskPath", f"{parsed.dag_id}:{parsed.task_id}"
    return "Task", parsed.task_id


def validate_task_equals(
    value: str,
    *,
    dag_names: set[str],
    dag_id_prefix: str,
    task_name_pattern,
    task_enum_values: set[str],
    built_task_prefixes: tuple[str, ...],
) -> list[str]:
    """Validate a Task[equals] YAML entry before routing expansion."""
    errors: list[str] = []
    label = f"Task[equals]: {value!r}"
    parsed = parse_task_criterion(value, dag_id_prefix)

    if is_pipeline_task(parsed.task_id):
        if not parsed.dag_id or parsed.is_global:
            errors.append(
                f"{label}: pipeline tasks (load-*, sync-*) "
                "must use bietlejuice.<dag>:<task>, "
                "not bietlejuice.*."
            )
        elif not _is_valid_task_id(
            parsed.task_id, task_name_pattern, task_enum_values, built_task_prefixes
        ):
            errors.append(f"{label}: invalid task id {parsed.task_id!r}.")
        elif not _dag_exists(parsed.dag_id, dag_id_prefix, dag_names):
            errors.append(
                f"{label}: DAG {parsed.dag_id!r} not found in dags/ "
                "(expected *_declaration.yml or dag package)."
            )
        return errors

    if is_general_task(parsed.task_id):
        if not parsed.is_global:
            errors.append(
                f"{label}: general tasks must use {dag_id_prefix}*:{parsed.task_id}."
            )
        return errors

    if not parsed.dag_id:
        errors.append(
            f"{label}: must use bietlejuice.<dag>:<task> or "
            f"{dag_id_prefix}*:<task> for cluster-wide tasks."
        )
        return errors

    if parsed.is_global:
        errors.append(
            f"{label}: only {sorted(JiraOpsEnum.GENERAL_TASK_IDS.value)} may use "
            f"{dag_id_prefix}*."
        )
        return errors

    if not _is_valid_task_id(
        parsed.task_id, task_name_pattern, task_enum_values, built_task_prefixes
    ):
        errors.append(f"{label}: invalid task id {parsed.task_id!r}.")
    if not _dag_exists(parsed.dag_id, dag_id_prefix, dag_names):
        errors.append(
            f"{label}: DAG {parsed.dag_id!r} not found in dags/ "
            "(expected *_declaration.yml or dag package)."
        )
    return errors


def validate_task_contains(
    value: str,
    *,
    dag_id_prefix: str = JiraOpsEnum.DAG_ID_PREFIX.value,
    dag_names: set[str] | None = None,
    task_name_pattern=None,
    task_enum_values: set[str] | None = None,
    built_task_prefixes: tuple[str, ...] | None = None,
) -> list[str]:
    errors: list[str] = []
    label = f"Task[contains]: {value!r}"
    parsed = parse_task_criterion(value, dag_id_prefix)

    if not parsed.dag_id:
        errors.append(
            f"{label}: must use {dag_id_prefix}*:<prefix> or "
            f"{dag_id_prefix}<dag>:<prefix>."
        )
        return errors

    if not parsed.is_global and dag_names is not None:
        if not _dag_exists(parsed.dag_id, dag_id_prefix, dag_names):
            errors.append(
                f"{label}: DAG {parsed.dag_id!r} not found in dags/ "
                "(expected *_declaration.yml or dag package)."
            )

    if not parsed.task_id.endswith(JiraOpsEnum.CONTAINS_SUFFIXES.value):
        errors.append(
            f"{label}: task prefix {parsed.task_id!r} must end with '_' or '-'."
        )

    if is_pipeline_task(parsed.task_id):
        errors.append(
            f"{label}: pipeline task prefixes (load-*, sync-*, etc.) "
            "cannot be muted via contains."
        )

    if (
        task_name_pattern is not None
        and task_enum_values is not None
        and built_task_prefixes is not None
        and not _is_valid_task_id(
            parsed.task_id,
            task_name_pattern,
            task_enum_values,
            built_task_prefixes,
        )
    ):
        errors.append(
            f"{label}: task prefix {parsed.task_id!r} is not a known built task prefix."
        )

    return errors


def _dag_exists(dag_id: str, dag_id_prefix: str, dag_names: set[str]) -> bool:
    return dag_id.removeprefix(dag_id_prefix) in dag_names


def _is_valid_task_id(
    task_id: str,
    task_name_pattern,
    task_enum_values: set[str],
    built_task_prefixes: tuple[str, ...],
) -> bool:
    if task_name_pattern.match(task_id) or task_id in task_enum_values:
        return True
    return any(
        task_id == prefix or task_id.startswith(prefix)
        for prefix in built_task_prefixes
    )
