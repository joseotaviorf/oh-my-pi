from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import pytest
from databricks_plugin.states.errors import DatabricksNotFoundError
from databricks_plugin.states.run_state import RunState
from requests.exceptions import HTTPError


def _build_operator():
    from databricks_plugin.operators.check_job_task import (
        QuintoAndarDatabricksCheckJobTaskOperator,
    )

    op = QuintoAndarDatabricksCheckJobTaskOperator(task_id="check_task", json={})
    op.xcom_push = MagicMock()
    return op


def _http_error(status_code: int, text: str) -> HTTPError:
    response = MagicMock()
    response.status_code = status_code
    response.text = text
    return HTTPError(text, response=response)


def _run_state(life_cycle_state, result_state=None, state_message=""):
    return RunState(
        life_cycle_state=life_cycle_state,
        state_message=state_message,
        result_state=result_state,
    )


def _execute_context():
    return {
        "task": MagicMock(execution_timeout=timedelta(hours=2)),
        "ti": MagicMock(start_date=datetime.now(timezone.utc)),
    }


def _prepare_execute_operator(op, mock_hook):
    op.databricks_hook = mock_hook
    op.run_id = 100
    op.job_id = 1
    op.execute_job_cluster_task_id = "execute_job_cluster"
    op._wait_polling_period = MagicMock()
    mock_hook.generate_run_page_url.return_value = "https://example.com/run"


def test_request_repair_active_run_returns_false():
    op = _build_operator()
    mock_hook = MagicMock()
    mock_hook.get_repair_id.return_value = 645658734632056
    mock_hook.repair_job_run.side_effect = _http_error(
        400,
        "{'error_code': 'INVALID_PARAMETER_VALUE', "
        "'message': 'Repair is not allowed on an active run'}",
    )
    op.databricks_hook = mock_hook

    result = op._request_repair(941086534825093, context={})

    assert result is False
    mock_hook.repair_job_run.assert_called_once_with(
        941086534825093,
        latest_repair_id=645658734632056,
        rerun_all_failed_tasks=True,
        version="2.1",
    )
    op.xcom_push.assert_not_called()


def test_request_repair_resource_conflict_returns_true():
    op = _build_operator()
    mock_hook = MagicMock()
    mock_hook.get_repair_id.return_value = 1
    mock_hook.repair_job_run.side_effect = _http_error(409, "RESOURCE_CONFLICT")
    op.databricks_hook = mock_hook

    result = op._request_repair(1, context={})

    assert result is True
    mock_hook.repair_job_run.assert_called_once_with(
        1,
        latest_repair_id=1,
        rerun_all_failed_tasks=True,
        version="2.1",
    )
    op.xcom_push.assert_not_called()


def test_request_repair_reraises_unmatched_http_error():
    op = _build_operator()
    mock_hook = MagicMock()
    mock_hook.get_repair_id.return_value = 1
    mock_hook.repair_job_run.side_effect = _http_error(
        400, "{'error_code': 'INVALID_PARAMETER_VALUE', 'message': 'boom'}"
    )
    op.databricks_hook = mock_hook

    with pytest.raises(HTTPError):
        op._request_repair(1, context={})


def test_request_repair_pushes_xcom_on_success():
    op = _build_operator()
    mock_hook = MagicMock()
    mock_hook.get_repair_id.return_value = 1
    mock_hook.repair_job_run.return_value = 2
    op.databricks_hook = mock_hook
    op._wait_polling_period = MagicMock()

    result = op._request_repair(1, context={})

    assert result is True
    mock_hook.repair_job_run.assert_called_once_with(
        1,
        latest_repair_id=1,
        rerun_all_failed_tasks=True,
        version="2.1",
    )
    op.xcom_push.assert_called_once_with({}, key=op.XCOM_LATEST_REPAIR_ID_KEY, value=2)


def test_monitor_latest_repair_execution_uses_task_repair_state():
    op = _build_operator()
    mock_hook = MagicMock()
    terminal_state = _run_state("TERMINATED", "FAILED")
    mock_hook.get_task_repair_state.return_value = terminal_state
    op.databricks_hook = mock_hook
    op._wait_polling_period = MagicMock()
    context = _execute_context()

    op._monitor_latest_repair_execution(
        100, 200, context["ti"].start_date, context["task"].execution_timeout
    )

    mock_hook.get_task_repair_state.assert_called_once_with(100, 200, version="2.1")
    mock_hook.get_job_run_task_state.assert_not_called()
    op._wait_polling_period.assert_not_called()


def test_monitor_latest_repair_execution_falls_back_to_job_run_state():
    op = _build_operator()
    mock_hook = MagicMock()
    mock_hook.get_task_repair_state.side_effect = DatabricksNotFoundError("missing")
    mock_hook.get_job_run_state.return_value = _run_state("TERMINATED", "FAILED")
    op.databricks_hook = mock_hook
    op._wait_polling_period = MagicMock()
    context = _execute_context()

    op._monitor_latest_repair_execution(
        100, 200, context["ti"].start_date, context["task"].execution_timeout
    )

    mock_hook.get_job_run_state.assert_called_once_with(100, version="2.1")
    op._wait_polling_period.assert_not_called()


def test_execute_failed_task_with_running_job_cancels_once_then_repairs():
    op = _build_operator()
    mock_hook = MagicMock()
    _prepare_execute_operator(op, mock_hook)

    failed_state = _run_state("TERMINATED", "FAILED")
    success_state = _run_state("TERMINATED", "SUCCESS")
    running_job = _run_state("RUNNING")
    terminal_job = _run_state("TERMINATED", "FAILED")

    mock_hook.get_job_run_task_state.side_effect = [
        failed_state,
        failed_state,
        failed_state,
        success_state,
    ]
    mock_hook.get_job_run_state.side_effect = [running_job, terminal_job]
    mock_hook.get_job_run_task_run_id.side_effect = [200, 200, 201, 201]
    mock_hook.get_task_repair_state.return_value = terminal_job
    mock_hook.get_repair_id.return_value = None
    mock_hook.repair_job_run.return_value = 1

    op.execute(_execute_context())

    mock_hook.cancel_job_run.assert_called_once_with(100, version="2.1")
    mock_hook.repair_job_run.assert_called_once_with(
        100,
        latest_repair_id=None,
        rerun_all_failed_tasks=True,
        version="2.1",
    )


def test_execute_failed_task_terminal_job_run_skips_cancel():
    op = _build_operator()
    mock_hook = MagicMock()
    _prepare_execute_operator(op, mock_hook)

    failed_state = _run_state("TERMINATED", "FAILED")
    success_state = _run_state("TERMINATED", "SUCCESS")
    terminal_job = _run_state("TERMINATED", "FAILED")

    mock_hook.get_job_run_task_state.side_effect = [
        failed_state,
        failed_state,
        failed_state,
        success_state,
    ]
    mock_hook.get_job_run_state.return_value = terminal_job
    mock_hook.get_job_run_task_run_id.side_effect = [200, 200, 201, 201]
    mock_hook.get_task_repair_state.return_value = terminal_job
    mock_hook.get_repair_id.return_value = None
    mock_hook.repair_job_run.return_value = 1

    op.execute(_execute_context())

    mock_hook.cancel_job_run.assert_not_called()
    mock_hook.repair_job_run.assert_called_once()


def test_execute_canceled_task_terminating_job_skips_cancel():
    op = _build_operator()
    mock_hook = MagicMock()
    _prepare_execute_operator(op, mock_hook)

    canceled_state = _run_state("TERMINATED", "CANCELED")
    success_state = _run_state("TERMINATED", "SUCCESS")
    terminating_job = _run_state("TERMINATING")
    terminal_job = _run_state("TERMINATED", "FAILED")

    mock_hook.get_job_run_task_state.side_effect = [
        canceled_state,
        canceled_state,
        canceled_state,
        success_state,
    ]
    mock_hook.get_job_run_state.side_effect = [terminating_job, terminal_job]
    mock_hook.get_job_run_task_run_id.side_effect = [200, 200, 201, 201]
    mock_hook.get_task_repair_state.return_value = terminal_job
    mock_hook.get_repair_id.return_value = None
    mock_hook.repair_job_run.return_value = 1

    op.execute(_execute_context())

    mock_hook.cancel_job_run.assert_not_called()
    mock_hook.repair_job_run.assert_called_once()


def test_execute_running_task_skips_cancel_and_repair():
    op = _build_operator()
    mock_hook = MagicMock()
    _prepare_execute_operator(op, mock_hook)

    running_state = _run_state("RUNNING")
    success_state = _run_state("TERMINATED", "SUCCESS")

    mock_hook.get_job_run_task_state.side_effect = [running_state, success_state]
    mock_hook.get_job_run_task_run_id.return_value = 200

    op.execute(_execute_context())

    mock_hook.cancel_job_run.assert_not_called()
    mock_hook.repair_job_run.assert_not_called()
    mock_hook.get_repair_id.assert_not_called()


def test_execute_repair_active_run_then_success_without_second_cancel():
    op = _build_operator()
    mock_hook = MagicMock()
    _prepare_execute_operator(op, mock_hook)

    failed_state = _run_state("TERMINATED", "FAILED")
    success_state = _run_state("TERMINATED", "SUCCESS")
    running_job = _run_state("RUNNING")
    terminal_job = _run_state("TERMINATED", "FAILED")
    active_run_error = _http_error(
        400,
        "{'error_code': 'INVALID_PARAMETER_VALUE', "
        "'message': 'Repair is not allowed on an active run'}",
    )

    mock_hook.get_job_run_task_state.side_effect = [
        failed_state,
        failed_state,
        failed_state,
        success_state,
    ]
    mock_hook.get_job_run_state.side_effect = [running_job, terminal_job]
    mock_hook.get_job_run_task_run_id.side_effect = [200, 200, 201, 201]
    mock_hook.get_task_repair_state.return_value = terminal_job
    mock_hook.get_repair_id.return_value = None
    mock_hook.repair_job_run.side_effect = [active_run_error, 1]

    op.execute(_execute_context())

    mock_hook.cancel_job_run.assert_called_once()
    assert mock_hook.repair_job_run.call_count == 2


def test_execute_stale_canceled_attempt_then_new_success():
    op = _build_operator()
    mock_hook = MagicMock()
    _prepare_execute_operator(op, mock_hook)

    failed_state = _run_state("TERMINATED", "FAILED")
    canceled_state = _run_state("TERMINATED", "CANCELED")
    running_state = _run_state("RUNNING")
    success_state = _run_state("TERMINATED", "SUCCESS")
    terminal_job = _run_state("TERMINATED", "FAILED")

    mock_hook.get_job_run_task_state.side_effect = [
        failed_state,
        canceled_state,
        running_state,
        success_state,
    ]
    mock_hook.get_job_run_state.return_value = terminal_job
    mock_hook.get_job_run_task_run_id.side_effect = [200, 200, 201, 201]
    mock_hook.get_task_repair_state.return_value = terminal_job
    mock_hook.get_repair_id.return_value = None
    mock_hook.repair_job_run.return_value = 1

    op.execute(_execute_context())

    mock_hook.cancel_job_run.assert_not_called()
    mock_hook.repair_job_run.assert_called_once()
