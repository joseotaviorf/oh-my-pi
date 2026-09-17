from __future__ import annotations

import json
from typing import Any

import requests
from quintoandar_logger import QuintoAndarLogger
from requests.auth import HTTPBasicAuth

logger = QuintoAndarLogger("JiraOpsClient")


class JiraOpsClient:
    # Default is the Data Engineering team
    DEFAULT_RESPONDER_TEAM_ID = "og-7c6d473a-9c80-4513-af76-9f2861cf966a"
    DEFAULT_ROUTING_RULE_ID = "b66439e7-adf8-4f30-afe6-563058a91b03"

    def __init__(self, credentials: dict[str, Any]) -> None:
        self.username = credentials["username"]
        self.token = credentials["token"]
        self.cloud_id = credentials["cloud_id"]

    def _auth_and_headers(self) -> tuple[HTTPBasicAuth, dict]:
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        return HTTPBasicAuth(self.username, self.token), headers

    def create_alert(
        self,
        message: str,
        description: str,
        tags: list[str],
        extra_properties: dict,
        responder_team_id: str | None = None,
        alias: str | None = None,
        priority: str | None = None,
    ) -> requests.Response:
        """
        Create an alert in JiraOps using the provided payload.

        Args:
            message: The message for the alert.
            description: The description of the alert.
            tags: List of tags to be associated with the alert.
            extra_properties: Additional properties to include in the alert.
            responder_team_id: JiraOps team ID for responders and visibility.
                Defaults to the Analytics Engineering team.
            alias: Optional client-defined identifier used by JSM Ops to
                de-duplicate alerts. When multiple alerts share the same alias,
                JSM Ops groups them into a single open alert instead of opening
                a new one. Omitted from the payload when not provided.
            priority: OpsGenie priority P1–P5; omitted → JSM default (P3).

        Returns:
            Response: The response from the JiraOps API.
        """
        url = f"https://api.atlassian.com/jsm/ops/api/{self.cloud_id}/v1/alerts"
        auth, headers = self._auth_and_headers()

        team_id = responder_team_id or self.DEFAULT_RESPONDER_TEAM_ID

        payload = {
            "message": message,
            "description": description,
            "responders": [{"id": team_id, "type": "team"}],
            "visibleTo": [{"id": team_id, "type": "team"}],
            "tags": tags,
            "extraProperties": extra_properties,
        }

        if alias is not None:
            payload["alias"] = alias

        if priority is not None:
            payload["priority"] = priority

        response = requests.post(
            url, data=json.dumps(payload), headers=headers, auth=auth
        )
        return response

    def update_team_routing_rule_criteria(
        self,
        criteria: dict,
        team_id: str = DEFAULT_RESPONDER_TEAM_ID,
        routing_rule_id: str = DEFAULT_ROUTING_RULE_ID,
    ) -> requests.Response:
        """
        Replace the criteria of a team routing rule in Jira Ops.

        Used to sync mute-list conditions (extra-properties contains DAG/Task/DAGOwner).
        """
        url = (
            f"https://api.atlassian.com/jsm/ops/api/{self.cloud_id}/v1/teams/"
            f"{team_id}/routing-rules/{routing_rule_id}"
        )
        auth, headers = self._auth_and_headers()

        response = requests.patch(
            url,
            data=json.dumps({"criteria": criteria}),
            headers=headers,
            auth=auth,
        )
        logger.info(
            "Updated routing rule %s for team %s (status=%s)",
            routing_rule_id,
            team_id,
            response.status_code,
        )
        return response

    def get_team_routing_rule(
        self,
        team_id: str,
        routing_rule_id: str = DEFAULT_ROUTING_RULE_ID,
    ) -> dict:
        """Fetch a team routing rule (used for lake ingestion and drift checks)."""
        url = (
            f"https://api.atlassian.com/jsm/ops/api/{self.cloud_id}/v1/teams/"
            f"{team_id}/routing-rules/{routing_rule_id}"
        )
        auth, headers = self._auth_and_headers()
        response = requests.get(url, headers=headers, auth=auth)
        response.raise_for_status()
        return response.json()
