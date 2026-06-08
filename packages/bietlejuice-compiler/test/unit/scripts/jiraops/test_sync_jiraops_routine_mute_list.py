from pathlib import Path
from unittest.mock import MagicMock

import pytest
import sync_jiraops_routine_mute_list as sync_module
from build_jiraops_mute_criteria import BuildJiraOpsMuteCriteria

from bietlejuice.base.jiraops.jiraops_client import JiraOpsClient


@pytest.fixture
def mute_list_yaml(tmp_path: Path) -> Path:
    path = tmp_path / "jiraops_mute_list.yml"
    path.write_text(
        """
DAG:
  equals:
    - bietlejuice.example_dag
Task: {}
DAGOwner: {}
""".strip(),
        encoding="utf-8",
    )
    return path


def test_main_requires_all_credential_env_vars(monkeypatch: pytest.MonkeyPatch):
    # Arrange
    monkeypatch.delenv(sync_module.JIRA_OPS_USERNAME, raising=False)
    monkeypatch.delenv(sync_module.JIRA_OPS_TOKEN, raising=False)
    monkeypatch.delenv(sync_module.JIRA_OPS_CLOUD_ID, raising=False)

    # Act
    exit_code = sync_module.main()

    # Assert
    assert exit_code == 1


def test_main_syncs_with_separate_env_vars(
    monkeypatch: pytest.MonkeyPatch, mute_list_yaml: Path
):
    # Arrange
    monkeypatch.setenv(sync_module.JIRA_OPS_USERNAME, "user@example.com")
    monkeypatch.setenv(sync_module.JIRA_OPS_TOKEN, "secret-token")
    monkeypatch.setenv(sync_module.JIRA_OPS_CLOUD_ID, "cloud-123")
    monkeypatch.setattr(
        sync_module,
        "BuildJiraOpsMuteCriteria",
        lambda: BuildJiraOpsMuteCriteria(mute_list_path=mute_list_yaml),
    )
    mock_client = MagicMock()
    mock_response = MagicMock()
    mock_client.update_team_routing_rule_criteria.return_value = mock_response
    monkeypatch.setattr(
        sync_module, "JiraOpsClient", MagicMock(return_value=mock_client)
    )

    # Act
    exit_code = sync_module.main()

    # Assert
    assert exit_code == 0
    sync_module.JiraOpsClient.assert_called_once_with(
        credentials={
            "username": "user@example.com",
            "token": "secret-token",
            "cloud_id": "cloud-123",
        }
    )
    mock_client.update_team_routing_rule_criteria.assert_called_once()
    criteria = mock_client.update_team_routing_rule_criteria.call_args.kwargs[
        "criteria"
    ]
    assert criteria["type"] == "match-any-condition"
    assert len(criteria["conditions"]) == 1
    mock_response.raise_for_status.assert_called_once()


def test_main_returns_error_when_api_raises(
    monkeypatch: pytest.MonkeyPatch, mute_list_yaml: Path
):
    # Arrange
    monkeypatch.setenv(sync_module.JIRA_OPS_USERNAME, "u")
    monkeypatch.setenv(sync_module.JIRA_OPS_TOKEN, "t")
    monkeypatch.setenv(sync_module.JIRA_OPS_CLOUD_ID, "c")
    monkeypatch.setattr(
        sync_module,
        "BuildJiraOpsMuteCriteria",
        lambda: BuildJiraOpsMuteCriteria(mute_list_path=mute_list_yaml),
    )
    mock_client = MagicMock()
    mock_client.update_team_routing_rule_criteria.side_effect = RuntimeError("API down")
    monkeypatch.setattr(
        sync_module, "JiraOpsClient", MagicMock(return_value=mock_client)
    )

    # Act
    exit_code = sync_module.main()

    # Assert
    assert exit_code == 1


def test_jira_ops_client_default_team_constants():
    # Assert
    assert JiraOpsClient.DEFAULT_RESPONDER_TEAM_ID.startswith("og-")
    assert JiraOpsClient.DEFAULT_ROUTING_RULE_ID
