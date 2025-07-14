import pytest
import datetime
from unittest.mock import patch, MagicMock

FAKE_TIME = datetime.datetime(2025, 5, 5, 12, 0, 0)


@pytest.fixture
def patch_datetime_now(monkeypatch):
    class fake_datetime(datetime.datetime):
        @classmethod
        def now(cls):
            return FAKE_TIME

    monkeypatch.setattr(datetime, "datetime", fake_datetime)


def get_mock_variable(key):
    if key == "environment":
        return "prod"
    return "test_api_key"


@pytest.fixture
def mock_airflow_variables():
    mock_variable = MagicMock()
    mock_variable.get.side_effect = get_mock_variable
    return mock_variable


@pytest.fixture
def opsgenie_callback(mock_airflow_variables, patch_datetime_now):
    with patch.dict(
        "sys.modules", {"airflow.models": MagicMock(Variable=mock_airflow_variables)}
    ):
        from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback

        yield OpsgenieCallback()


@pytest.fixture
def mock_requests_post():
    with patch("requests.post") as mock_post:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"result": "success"}
        mock_post.return_value = mock_response
        yield mock_post


def test_task_failure_alert(
    mock_airflow_variables, mock_requests_post, opsgenie_callback
):
    mock_context = {"task_instance": MagicMock(task_id="test_task", dag_id="test_dag")}

    opsgenie_callback.task_failure_alert(mock_context)

    mock_airflow_variables.get.assert_any_call("environment")
    mock_airflow_variables.get.assert_any_call("OPSGENIE_ONCALL_APIKEY")

    # Ensure the request was made to Opsgenie
    mock_requests_post.assert_called_once()

    args, kwargs = mock_requests_post.call_args
    assert (
        "https://api.opsgenie.com/v1/json/googlestackdriver?apiKey=test_api_key"
        in args[0]
    )
    assert kwargs["headers"] == {"Content-Type": "application/json"}
    assert kwargs["json"]["incident"] == {
        "resource_name": "labels {workflow_name=test_dag}",
        "state": "open",
        "started_at": datetime.datetime.timestamp(FAKE_TIME),
        "summary": "DAG: test_dag - Task: test_task",
        "description": f"DAG: test_dag - Task: test_task Started At: 2025-05-05 12:00:00 . Prometheus: https://prometheus.apps.core-prd.habitat.zone/",
        "metric": {"labels": {"task_name": "test_task", "state": "failed"}},
        "resource": {"labels": {"workflow_name": "test_dag"}},
    }
