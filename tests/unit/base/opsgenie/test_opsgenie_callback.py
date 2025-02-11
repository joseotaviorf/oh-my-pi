import pytest
from unittest.mock import patch, MagicMock


def get_mock_variable(key):
    if key == "environment":
        return "prod"
    return "test_api_key"


mock_variable = MagicMock()
mock_variable.get.side_effect = get_mock_variable

with patch.dict("sys.modules", {"airflow.models": MagicMock(Variable=mock_variable)}):
    from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback


@pytest.fixture
def mock_airflow_variables():
    yield mock_variable.get


@pytest.fixture
def mock_requests_post():
    with patch("requests.post") as mock_post:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"result": "success"}
        mock_post.return_value = mock_response
        yield mock_post


def test_task_failure_alert(mock_airflow_variables, mock_requests_post):
    callback = OpsgenieCallback()

    mock_context = {"task_instance": MagicMock(task_id="test_task", dag_id="test_dag")}

    callback.task_failure_alert(mock_context)

    mock_airflow_variables.assert_any_call("environment")
    mock_airflow_variables.assert_any_call("OPSGENIE_ONCALL_APIKEY")

    # Ensure the request was made to Opsgenie
    mock_requests_post.assert_called_once()

    args, kwargs = mock_requests_post.call_args
    assert (
        "https://api.opsgenie.com/v1/json/googlestackdriver?apiKey=test_api_key"
        in args[0]
    )
    assert kwargs["headers"] == {"Content-Type": "application/json"}
    assert "incident" in kwargs["json"]
