from unittest.mock import MagicMock

import pytest
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


def test_request_repair_swallows_repair_not_allowed_on_active_run():
    """Regression: production returns error_code=INVALID_PARAMETER_VALUE with the
    message 'Repair is not allowed on an active run' when the run/task hasn't
    fully transitioned out of its terminal state yet, or another operator
    invocation is already repairing it. This must be logged and swallowed, not
    raised, matching the sibling 409 RESOURCE_CONFLICT branch above it.
    """
    op = _build_operator()
    mock_hook = MagicMock()
    mock_hook.get_repair_id.return_value = 645658734632056
    mock_hook.repair_job_run.side_effect = _http_error(
        400,
        "{'error_code': 'INVALID_PARAMETER_VALUE', "
        "'message': 'Repair is not allowed on an active run'}",
    )
    op.databricks_hook = mock_hook

    op._request_repair(941086534825093, context={})

    op.xcom_push.assert_not_called()


def test_request_repair_swallows_resource_conflict():
    """409 RESOURCE_CONFLICT (already being repaired) must also be swallowed."""
    op = _build_operator()
    mock_hook = MagicMock()
    mock_hook.get_repair_id.return_value = 1
    mock_hook.repair_job_run.side_effect = _http_error(409, "RESOURCE_CONFLICT")
    op.databricks_hook = mock_hook

    op._request_repair(1, context={})

    op.xcom_push.assert_not_called()


def test_request_repair_reraises_unmatched_http_error():
    """Any other HTTPError (unrelated 400s, 5xx, etc.) must still propagate."""
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

    op._request_repair(1, context={})

    op.xcom_push.assert_called_once_with({}, key=op.XCOM_LATEST_REPAIR_ID_KEY, value=2)
