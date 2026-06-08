import json

import pytest
from jiraops_credentials import (
    JIRA_OPS_CLOUD_ID,
    JIRA_OPS_CREDENTIALS_JSON,
    JIRA_OPS_TOKEN,
    JIRA_OPS_USERNAME,
    load_jiraops_credentials,
)


def test_load_from_json_blob(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv(
        JIRA_OPS_CREDENTIALS_JSON,
        json.dumps(
            {
                "username": "user@example.com",
                "token": "secret",
                "cloud_id": "cloud-1",
            }
        ),
    )
    monkeypatch.delenv(JIRA_OPS_USERNAME, raising=False)
    monkeypatch.delenv(JIRA_OPS_TOKEN, raising=False)
    monkeypatch.delenv(JIRA_OPS_CLOUD_ID, raising=False)

    credentials = load_jiraops_credentials()

    assert credentials == {
        "username": "user@example.com",
        "token": "secret",
        "cloud_id": "cloud-1",
    }


def test_load_from_flat_env_vars(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.delenv(JIRA_OPS_CREDENTIALS_JSON, raising=False)
    monkeypatch.setenv(JIRA_OPS_USERNAME, "user@example.com")
    monkeypatch.setenv(JIRA_OPS_TOKEN, "secret")
    monkeypatch.setenv(JIRA_OPS_CLOUD_ID, "cloud-1")

    credentials = load_jiraops_credentials()

    assert credentials == {
        "username": "user@example.com",
        "token": "secret",
        "cloud_id": "cloud-1",
    }


def test_json_blob_takes_precedence_over_flat_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv(
        JIRA_OPS_CREDENTIALS_JSON,
        json.dumps(
            {
                "username": "from-json",
                "token": "json-token",
                "cloud_id": "json-cloud",
            }
        ),
    )
    monkeypatch.setenv(JIRA_OPS_USERNAME, "from-flat")
    monkeypatch.setenv(JIRA_OPS_TOKEN, "flat-token")
    monkeypatch.setenv(JIRA_OPS_CLOUD_ID, "flat-cloud")

    credentials = load_jiraops_credentials()

    assert credentials["username"] == "from-json"


def test_raises_when_no_credentials(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.delenv(JIRA_OPS_CREDENTIALS_JSON, raising=False)
    monkeypatch.delenv(JIRA_OPS_USERNAME, raising=False)
    monkeypatch.delenv(JIRA_OPS_TOKEN, raising=False)
    monkeypatch.delenv(JIRA_OPS_CLOUD_ID, raising=False)

    with pytest.raises(ValueError, match="Jira Ops credentials not found"):
        load_jiraops_credentials()


def test_raises_on_invalid_json(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv(JIRA_OPS_CREDENTIALS_JSON, "not-json")

    with pytest.raises(ValueError, match="not valid JSON"):
        load_jiraops_credentials()


def test_raises_on_missing_keys(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv(
        JIRA_OPS_CREDENTIALS_JSON,
        json.dumps({"username": "user@example.com"}),
    )

    with pytest.raises(ValueError, match="missing required keys"):
        load_jiraops_credentials()
