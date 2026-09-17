import datetime
import json
from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.base.airflow.enums.dag_run_type_enum import DagRunTypeEnum
from bietlejuice.base.incident_context_enrichers.jira.jira_enricher import JiraEnricher
from bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service import (
    JiraIncidentOwnerService,
)

FAKE_TIME = datetime.datetime(2025, 5, 5, 12, 0, 0)


def get_mock_variable(key):
    if key == "environment":
        return "prod"
    if key == "JIRA_OPS_ONCALL_APIKEY":
        return json.dumps(
            {
                "username": "test_username",
                "token": "test_token",
                "cloud_id": "test_cloud_id",
            }
        )
    return None


@pytest.fixture()
def mock_airflow_variables():
    mock_variable = MagicMock()
    mock_variable.get.side_effect = get_mock_variable
    return mock_variable


def mock_context():
    task_instance = MagicMock()
    task = MagicMock()
    task_instance.task = task
    task.task_id = "test_task"
    task.owner = "Data Agents"
    task_instance.dag_id = "test_dag"
    dag_run = MagicMock()
    dag_run.run_type = "manual"
    task_instance.dag_run = dag_run
    return {"task_instance": task_instance, "params": {}}


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
@patch(
    "bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service.JiraIncidentOwnerService.sync_incident_owner_options"
)
@patch.object(JiraIncidentOwnerService, "_get_context_id", return_value="ctx-1")
@patch("bietlejuice.base.jiraops.jiraops_callback.JiraOpsClient")
def test_callback_runs_jira_enricher_then_creates_alert(
    mock_client_class,
    mock_context_id,
    mock_sync,
    mock_get_run_type,
    mock_airflow_variables,
):
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_client_class.return_value.create_alert.return_value = mock_response

    class fake_datetime(datetime.datetime):
        @classmethod
        def now(cls, tz=None):
            return FAKE_TIME

    with (
        patch(
            "bietlejuice.base.jiraops.jiraops_callback.Variable", mock_airflow_variables
        ),
        patch(
            "bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service.Variable",
            mock_airflow_variables,
        ),
        patch("bietlejuice.base.jiraops.jiraops_callback.datetime", fake_datetime),
    ):
        from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback

        callback = JiraOpsCallback().add_context_enricher(JiraEnricher())
        callback.task_failure_alert(mock_context())

    mock_sync.assert_called_once()
    mock_client_class.return_value.create_alert.assert_called_once()
    call_kwargs = mock_client_class.return_value.create_alert.call_args.kwargs
    assert call_kwargs["extra_properties"]["DAG"] == "test_dag"
    assert call_kwargs["extra_properties"]["DAGOwner"] == "Data Agents"
    assert call_kwargs["extra_properties"]["Criticality"] == "Medium"
    assert call_kwargs["priority"] == "P3"
