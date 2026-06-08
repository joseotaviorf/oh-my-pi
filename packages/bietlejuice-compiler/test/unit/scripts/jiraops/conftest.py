import sys
from pathlib import Path

import pytest

_COMPILER_ROOT = Path(__file__).resolve().parents[4]
_SCRIPTS_JIRAOPS = _COMPILER_ROOT / "scripts/jiraops"
for path in (_COMPILER_ROOT, _SCRIPTS_JIRAOPS):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))


@pytest.fixture
def empty_dependency_graph():
    from scripts.dependency_handling.validate_dependencies_exist import DependencyGraph

    return DependencyGraph()


@pytest.fixture
def validator_factory(empty_dependency_graph):
    """Build a validator instance without loading the repo mute list."""

    def _factory(
        mute_list: dict,
        dag_names: set[str] | None = None,
        routine_exceptions: dict | None = None,
    ):
        from validate_jiraops_routine_mute_list import JiraOpsRoutineMuteListValidator

        from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
        from scripts.jiraops.jiraops_enum import JiraOpsEnum
        from scripts.jiraops.validate_jiraops_routine_exceptions import (
            JiraOpsRoutineExceptionsValidator,
        )

        validator = JiraOpsRoutineMuteListValidator.__new__(
            JiraOpsRoutineMuteListValidator
        )
        validator.mute_list_path = JiraOpsEnum.JIRA_OPS_MUTE_LIST_PATH.value
        validator.mute_list = mute_list
        validator.dag_names = dag_names or set()
        validator.dag_owners = {}
        validator.task_upstream_dags = {}
        validator.dependency_graph = empty_dependency_graph
        validator.valid_owners = set(DAGOwnerEnum.get_available_enum_values())
        validator.errors = []
        validator.expected_extra_property_keys = (
            JiraOpsEnum.JIRA_OPS_EXTRA_PROPERTY_KEYS.value
        )
        validator.allowed_operations = JiraOpsEnum.ALLOWED_OPERATIONS.value
        validator.contains_suffixes = JiraOpsEnum.CONTAINS_SUFFIXES.value
        validator.dag_id_prefix = JiraOpsEnum.DAG_ID_PREFIX.value
        validator.routine_exceptions_path = (
            JiraOpsEnum.JIRA_OPS_ROUTINE_EXCEPTIONS_PATH.value.name
        )
        validator.task_name_pattern = JiraOpsEnum._TASK_NAME_PATTERN.value
        validator.built_task_prefixes = JiraOpsEnum._BUILT_TASK_PREFIXES.value
        validator.routine_exceptions_validator = JiraOpsRoutineExceptionsValidator(
            routine_exceptions=routine_exceptions or {}
        )
        return validator

    return _factory


@pytest.fixture
def minimal_mute_list() -> dict:
    return {
        "DAG": {"equals": [], "contains": []},
        "Task": {"equals": [], "contains": []},
        "DAGOwner": {"equals": []},
    }
