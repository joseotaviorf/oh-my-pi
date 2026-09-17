"""Unit tests for JiraOpsClient.create_alert payload building."""

import json
from unittest import mock

import pytest

from bietlejuice.base.jiraops.jiraops_client import JiraOpsClient

_CREDENTIALS = {
    "username": "bot@quintoandar.com.br",
    "token": "fake-token",
    "cloud_id": "fake-cloud-id",
}


@pytest.fixture
def client():
    return JiraOpsClient(_CREDENTIALS)


def _posted_payload(mock_post):
    _, kwargs = mock_post.call_args
    return json.loads(kwargs["data"])


@mock.patch("bietlejuice.base.jiraops.jiraops_client.requests.post")
def test_create_alert_omits_alias_by_default(mock_post, client):
    client.create_alert(
        message="msg",
        description="desc",
        tags=["dag_x"],
        extra_properties={"DAG": "dag_x"},
    )

    payload = _posted_payload(mock_post)
    assert "alias" not in payload
    assert "priority" not in payload
    assert payload["message"] == "msg"
    assert payload["extraProperties"] == {"DAG": "dag_x"}


@mock.patch("bietlejuice.base.jiraops.jiraops_client.requests.post")
def test_create_alert_omits_priority_by_default(mock_post, client):
    client.create_alert(
        message="msg",
        description="desc",
        tags=["dag_x"],
        extra_properties={"DAG": "dag_x"},
    )

    payload = _posted_payload(mock_post)
    assert "priority" not in payload


@mock.patch("bietlejuice.base.jiraops.jiraops_client.requests.post")
def test_create_alert_includes_priority_when_provided(mock_post, client):
    client.create_alert(
        message="msg",
        description="desc",
        tags=["dag_x"],
        extra_properties={"DAG": "dag_x"},
        priority="P1",
    )

    payload = _posted_payload(mock_post)
    assert payload["priority"] == "P1"


@mock.patch("bietlejuice.base.jiraops.jiraops_client.requests.post")
def test_create_alert_includes_alias_when_provided(mock_post, client):
    client.create_alert(
        message="msg",
        description="desc",
        tags=["dag_x"],
        extra_properties={"DAG": "dag_x"},
        alias="dag-runtime-dag_x-run_1",
    )

    payload = _posted_payload(mock_post)
    assert payload["alias"] == "dag-runtime-dag_x-run_1"


@mock.patch("bietlejuice.base.jiraops.jiraops_client.requests.post")
def test_create_alert_defaults_to_data_engineering_team(mock_post, client):
    client.create_alert(
        message="msg",
        description="desc",
        tags=[],
        extra_properties={},
    )

    payload = _posted_payload(mock_post)
    assert payload["responders"] == [
        {"id": JiraOpsClient.DEFAULT_RESPONDER_TEAM_ID, "type": "team"}
    ]
    assert payload["visibleTo"] == [
        {"id": JiraOpsClient.DEFAULT_RESPONDER_TEAM_ID, "type": "team"}
    ]
