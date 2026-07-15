import enum
import re
from pathlib import Path

from bietlejuice.base.airflow.base_task_group import BaseTaskGroup


class JiraOpsEnum(enum.Enum):
    # slugify output used by generate_default_task_id and task creators (e.g. load-clean-address)
    _TASK_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]*$")

    # prefixes from BaseTaskGroup + task creator _TASK_ID_TEMPLATE (built DAG tasks)
    _BUILT_TASK_PREFIXES = (
        f"{BaseTaskGroup.LOAD_TASK_PREFIX}-",
        BaseTaskGroup.SYNC_METADATA_TASK_PREFIX,
        BaseTaskGroup.DATA_QUALITY_TESTS_TASK_PREFIX,
        BaseTaskGroup.ADD_DEFAULT_ROW_TASK_PREFIX,
        "register-table-",
        "register-",
        "optimize-",
        "build-qube-",
        "create-query-view-",
        "execute-job-cluster",
        "job-cluster-finished",
        "terminate-cluster",
        "terminate-emr-cluster",
    )

    DAG_ID_PREFIX = "bietlejuice."

    CONTAINS_SUFFIXES = ("_", "-", ".")
    ALLOWED_OPERATIONS = frozenset({"equals", "contains"})
    REQUIRED_EXCEPTION_FIELDS = frozenset(
        {"reason", "deadline", "created_by", "approved_by"}
    )
    DEADLINE_DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")
    DEADLINE_NEVER = "Never"
    # ``deadline``: last calendar day the exception remains valid, or ``Never`` if open-ended.

    JIRA_OPS_MUTE_LIST_KEYS = ("DAG", "Task", "DAGOwner")
    JIRA_OPS_EXTRA_PROPERTY_KEYS = (
        JIRA_OPS_MUTE_LIST_KEYS  # YAML mute list / exceptions
    )

    GLOBAL_DAG_WILDCARD_SUFFIX = "*"
    FORBIDDEN_PIPELINE_TASK_PREFIXES = (
        "load-",
        "sync-",
        "execute-job-cluster",
    )
    GENERAL_TASK_IDS = frozenset(
        {"job-cluster-finished", "terminate-cluster", "terminate-emr-cluster"}
    )
    JIRA_OPS_MUTE_LIST_PATH = Path(__file__).resolve().parent / "jiraops_mute_list.yml"
    JIRA_OPS_ROUTINE_EXCEPTIONS_PATH = (
        Path(__file__).resolve().parent / "jiraops_mute_list_exceptions.yml"
    )

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]
