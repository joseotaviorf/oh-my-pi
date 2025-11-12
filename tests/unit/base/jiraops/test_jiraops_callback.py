import json
import pytest
import datetime
import pendulum
from unittest.mock import patch, MagicMock
from bietlejuice.base.airflow.enums.dag_run_type_enum import DagRunTypeEnum

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
        return json.dumps(
            {
                "username": "test_username",
                "token": "test_token",
                "cloud_id": "test_cloud_id",
            }
        )
    return None


@pytest.fixture
def mock_airflow_variables():
    mock_variable = MagicMock()
    mock_variable.get.side_effect = get_mock_variable
    return mock_variable


@pytest.fixture
def mock_jiraops_client():
    with patch(
        "bietlejuice.base.jiraops.jiraops_client.JiraOpsClient"
    ) as mock_client_class:
        mock_client_instance = MagicMock()
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"result": "success"}
        mock_client_instance.create_alert.return_value = mock_response
        mock_client_class.return_value = mock_client_instance
        yield mock_client_class, mock_client_instance


def mock_context():
    dataset_alias = MagicMock()
    dataset_alias.name = "dag:task:alias"
    task_instance = MagicMock()
    task_instance.xcom_pull.return_value = None
    task = MagicMock()
    task_instance.task = task
    task.task_id = "test_task"
    task.owner = "testOwner"
    dag = MagicMock()
    dag.dag_id = "test_dag"
    outlet_event_accessor = MagicMock()
    task_instance.task_id = task.task_id = "test_task"
    task_instance.dag_id = "test_dag"
    task_instance.start_date = pendulum.datetime(2025, 1, 2)
    dag_run = MagicMock()
    dag_run.run_id = "manual__2025-01-01T00:00:00+00:00"
    dag_run.run_type = "manual"
    task_instance.dag_run = dag_run

    return {
        "params": {"run_type": "test_run"},
        "outlets": [dataset_alias],
        "outlet_events": {"dag:task:alias": outlet_event_accessor},
        "triggering_dataset_events": {},
        "execution_date": pendulum.datetime(2025, 1, 1),
        "ti": task_instance,
        "task": task,
        "dag_run": dag_run,
        "dag": dag,
        "task_instance": task_instance,
    }


@pytest.fixture
def jiraops_callback(mock_airflow_variables, patch_datetime_now):
    with patch.dict(
        "sys.modules", {"airflow.models": MagicMock(Variable=mock_airflow_variables)}
    ):
        from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback

        yield JiraOpsCallback()


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_task_failure_alert_prod_environment(
    mock_get_run_type, mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    # Mock the run type to return IMPACT_DOWNSTREAM_DEPENDENTS (not TEST_RUN)
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS

    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.task_failure_alert(context)

    # Verify that _get_run_type was called with the context
    mock_get_run_type.assert_called_once_with(context)

    mock_airflow_variables.get.assert_any_call("environment")
    mock_airflow_variables.get.assert_any_call("JIRA_OPS_ONCALL_APIKEY")

    expected_credentials = {
        "username": "test_username",
        "token": "test_token",
        "cloud_id": "test_cloud_id",
    }
    mock_client_class.assert_called_once_with(expected_credentials)

    expected_message = "DAG: test_dag - Task: test_task"
    expected_description = "DAG: test_dag - Task: test_task at: 2025-05-05 12:00:00"
    expected_tags = ["test_dag", "test_task", "task failed"]

    expected_extra_properties = {
        "DAG": "test_dag",
        "Task": "test_task",
        "DAGOwner": "testOwner",
    }

    mock_client_instance.create_alert.assert_called_once_with(
        message=expected_message,
        description=expected_description,
        tags=expected_tags,
        extra_properties=expected_extra_properties,
    )


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_task_failure_alert_test_run_skips_alert(
    mock_get_run_type, mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    # Mock the run type to return TEST_RUN
    mock_get_run_type.return_value = DagRunTypeEnum.TEST_RUN

    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.task_failure_alert(context)

    # Verify that _get_run_type was called with the context
    mock_get_run_type.assert_called_once_with(context)

    # Verify that environment was checked
    mock_airflow_variables.get.assert_any_call("environment")

    # Alert should NOT be created for TEST_RUN
    mock_client_class.assert_not_called()
    mock_client_instance.create_alert.assert_not_called()


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_task_failure_alert_non_prod_environment_skips_alert(
    mock_get_run_type, mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    # Mock the run type to return IMPACT_DOWNSTREAM_DEPENDENTS
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS

    # Mock environment to be non-prod
    def get_mock_variable_non_prod(key):
        if key == "environment":
            return "forno"  # Non-prod environment
        elif key == "JIRA_OPS_ONCALL_APIKEY":
            return json.dumps(
                {
                    "username": "test_username",
                    "token": "test_token",
                    "cloud_id": "test_cloud_id",
                }
            )
        return None

    mock_airflow_variables.get.side_effect = get_mock_variable_non_prod

    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.task_failure_alert(context)

    # Verify that _get_run_type was called with the context
    mock_get_run_type.assert_called_once_with(context)

    # Verify that environment was checked
    mock_airflow_variables.get.assert_any_call("environment")

    # Alert should NOT be created for non-prod environment
    mock_client_class.assert_not_called()
    mock_client_instance.create_alert.assert_not_called()
