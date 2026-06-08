import json
from unittest.mock import MagicMock, patch

import pytest
import requests

from bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service import (
    JIRA_OPS_AIRFLOW_VARIABLE,
    JiraIncidentOwnerService,
)


def _mock_response(status_code: int, json_body: dict) -> MagicMock:
    response = MagicMock(spec=requests.Response)
    response.status_code = status_code
    response.json.return_value = json_body
    response.raise_for_status = MagicMock()
    if status_code >= 400:
        response.raise_for_status.side_effect = requests.HTTPError(response=response)
    return response


@pytest.fixture
def service() -> JiraIncidentOwnerService:
    with patch(
        "bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service.Variable.get",
        return_value=json.dumps(
            {"username": "user@example.com", "token": "token", "cloud_id": "cloud-123"}
        ),
    ):
        with patch.object(
            JiraIncidentOwnerService, "_get_context_id", return_value="ctx-1"
        ):
            svc = JiraIncidentOwnerService()
            svc._session = MagicMock(spec=requests.Session)
            yield svc


class TestComputeSyncDiff:
    def test_creates_and_deletes_diff(self):
        create, delete = JiraIncidentOwnerService.compute_sync_diff(
            desired_values=["Data Agents", "Data Growth"],
            current_options={"Data Agents": "1", "Data People": "2"},
        )
        assert create == [{"value": "Data Growth"}]
        assert delete == ["2"]


class TestJiraIncidentOwnerService:
    @patch(
        "bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service.Variable.get",
        return_value=json.dumps({"username": "u", "token": "t", "cloud_id": "cloud-1"}),
    )
    def test_uses_jira_ops_oncall_variable(self, mock_variable_get):
        with patch.object(
            JiraIncidentOwnerService, "_get_context_id", return_value="ctx-1"
        ):
            service = JiraIncidentOwnerService()

        mock_variable_get.assert_called_once_with(JIRA_OPS_AIRFLOW_VARIABLE)
        assert service._base_url == "https://quintoandar.atlassian.net"

    def test_list_field_options(self, service):
        service._session.request.return_value = _mock_response(
            200,
            {
                "values": [
                    {"id": "opt-1", "value": "Data Agents"},
                    {"id": "opt-2", "value": "Data Growth"},
                ]
            },
        )

        options = service.list_field_options()
        assert options == {"Data Agents": "opt-1", "Data Growth": "opt-2"}

    @patch(
        "bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service.DAGOwnerEnum.get_available_enum_values",
        return_value=["Data Agents", "Data Growth"],
    )
    def test_sync_incident_owner_options(self, mock_enum, service):
        service._session.request.side_effect = [
            _mock_response(
                200,
                {"values": [{"id": "opt-1", "value": "Data Agents"}]},
            ),
            _mock_response(200, {"options": [{"id": "opt-2", "value": "Data Growth"}]}),
        ]

        service.sync_incident_owner_options()

        assert service._session.request.call_count == 2
