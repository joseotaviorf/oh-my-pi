from unittest.mock import MagicMock

from bietlejuice.base.incident_context.databricks.databricks_run_error_service import (
    DEFAULT_ERROR_MESSAGE,
    DatabricksRunErrorService,
)


def _make_service(job_run_metadata):
    hook = MagicMock()
    return (
        DatabricksRunErrorService(
            dag_id="test_dag",
            job_run_metadata=job_run_metadata,
            databricks_hook=hook,
        ),
        hook,
    )


def test_extracts_common_error():
    metadata = {
        "run_id": "100",
        "tasks": [{"run_id": "200", "task_key": "load"}],
    }
    service, hook = _make_service(metadata)
    hook.jobs_client.client.get_run_output.return_value = {
        "error": "SparkException: OOM"
    }

    result = service.get_databricks_run_error()

    assert result == "Task 'load': SparkException: OOM"


def test_extracts_timed_out_error():
    metadata = {
        "run_id": "100",
        "tasks": [{"run_id": "200", "task_key": "load"}],
    }
    service, hook = _make_service(metadata)
    hook.jobs_client.client.get_run_output.return_value = {
        "error": None,
        "metadata": {"state": {"state_message": "Run timed out"}},
    }

    result = service.get_databricks_run_error()

    assert result == "Task 'load': Run timed out"


def test_falls_back_to_default_when_no_error():
    metadata = {
        "run_id": "100",
        "tasks": [{"run_id": "200", "task_key": "load"}],
    }
    service, hook = _make_service(metadata)
    hook.jobs_client.client.get_run_output.return_value = {}

    result = service.get_databricks_run_error()

    assert result == f"Task 'load': {DEFAULT_ERROR_MESSAGE}"


def test_concatenates_multiple_task_errors():
    metadata = {
        "run_id": "100",
        "tasks": [
            {"run_id": "200", "task_key": "load"},
            {"run_id": "201", "task_key": "optimize"},
        ],
    }
    service, hook = _make_service(metadata)
    hook.jobs_client.client.get_run_output.side_effect = [
        {"error": "error_1"},
        {"error": "error_2"},
    ]

    result = service.get_databricks_run_error()

    assert result == "Task 'load': error_1; Task 'optimize': error_2"
