import json
from unittest.mock import patch

from bietlejuice.base.incident_context_enrichers.jira.jira_enricher import JiraEnricher
from bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service import (
    JiraIncidentOwnerService,
)


@patch(
    "bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service.JiraIncidentOwnerService.sync_incident_owner_options"
)
@patch.object(JiraIncidentOwnerService, "_get_context_id", return_value="ctx-1")
@patch(
    "bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service.Variable.get",
    return_value=json.dumps({"username": "u", "token": "t", "cloud_id": "cloud-1"}),
)
def test_enrich_syncs_and_preserves_payload(
    mock_variable_get, mock_context_id, mock_sync
):
    enricher = JiraEnricher()
    extra = {"DAG": "bietlejuice.test", "DAGOwner": "Data Agents"}
    description = "DAG failed"

    out_extra, out_desc = enricher.enrich({}, extra, description)

    mock_sync.assert_called_once()
    assert out_extra == extra
    assert out_desc == description


@patch(
    "bietlejuice.base.incident_context_enrichers.jira.jira_incident_owner_service.Variable.get",
    side_effect=KeyError("missing"),
)
def test_enrich_failure_does_not_break_alert(mock_variable_get):
    enricher = JiraEnricher()
    extra = {"DAG": "x"}
    description = "fail"

    out_extra, out_desc = enricher.enrich({}, extra, description)

    assert out_extra == extra
    assert out_desc == description
