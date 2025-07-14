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
    elif key == "JIRA_OPS_ONCALL_APIKEY":
        return {
            "username": "test_username",
            "token": "test_token",
            "cloud_id": "test_cloud_id",
        }
    return None


@pytest.fixture
def mock_airflow_variables():
    mock_variable = MagicMock()
    mock_variable.get.side_effect = get_mock_variable
    return mock_variable


@pytest.fixture
def mock_jiraops_client():
    with patch(
        "bietlejuice.base.jira_ops.jiraops_client.JiraOpsClient"
    ) as mock_client_class:
        mock_client_instance = MagicMock()
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"result": "success"}
        mock_client_instance.create_alert.return_value = mock_response
        mock_client_class.return_value = mock_client_instance
        yield mock_client_class, mock_client_instance


@pytest.fixture
def jiraops_callback(mock_airflow_variables, patch_datetime_now):
    with patch.dict(
        "sys.modules", {"airflow.models": MagicMock(Variable=mock_airflow_variables)}
    ):
        from bietlejuice.base.jira_ops.jiraops_callback import JiraOpsCallback

        yield JiraOpsCallback()


def test_task_failure_alert_prod_environment(
    mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    mock_client_class, mock_client_instance = mock_jiraops_client
    mock_context = {"task_instance": MagicMock(task_id="test_task", dag_id="test_dag")}

    jiraops_callback.task_failure_alert(mock_context)

    mock_airflow_variables.get.assert_any_call("environment")
    mock_airflow_variables.get.assert_any_call("JIRA_OPS_ONCALL_APIKEY")

    expected_credentials = {
        "username": "test_username",
        "token": "test_token",
        "cloud_id": "test_cloud_id",
    }
    mock_client_class.assert_called_once_with(expected_credentials)

    expected_message = "DAG: test_dag - Task: test_task"
    expected_description = (
        "DAG: test_dag - Task: test_task Failed at: 2025-05-05 12:00:00"
    )
    expected_tags = ["test_dag", "test_task", "task failed"]

    mock_client_instance.create_alert.assert_called_once_with(
        message=expected_message, description=expected_description, tags=expected_tags
    )


def test_task_failure_alert_non_prod_environment(
    mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    def get_mock_variable_non_prod(key):
        if key == "environment":
            return "dev"
        elif key == "JIRA_OPS_ONCALL_APIKEY":
            return {
                "username": "test_username",
                "token": "test_token",
                "cloud_id": "test_cloud_id",
            }
        return None

    mock_airflow_variables.get.side_effect = get_mock_variable_non_prod
    mock_client_class, mock_client_instance = mock_jiraops_client
    mock_context = {"task_instance": MagicMock(task_id="test_task", dag_id="test_dag")}

    jiraops_callback.task_failure_alert(mock_context)

    mock_airflow_variables.get.assert_called_once_with("environment")
    mock_client_class.assert_not_called()
    mock_client_instance.create_alert.assert_not_called()


def test_task_failure_alert_client_error_response(
    mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    mock_client_class, mock_client_instance = mock_jiraops_client

    mock_response = MagicMock()
    mock_response.status_code = 400
    mock_response.text = "Bad Request"
    mock_client_instance.create_alert.return_value = mock_response

    mock_context = {"task_instance": MagicMock(task_id="test_task", dag_id="test_dag")}

    jiraops_callback.task_failure_alert(mock_context)

    mock_client_instance.create_alert.assert_called_once()
