import json
import requests
from requests.auth import HTTPBasicAuth

from quintoandar_logger import QuintoAndarLogger


logger = QuintoAndarLogger("JiraOpsClient")


class JiraOpsClient:
    # Default is the Analytics Engineering team
    DEFAULT_RESPONDER_TEAM_ID = "og-7c6d473a-9c80-4513-af76-9f2861cf966a"

    def __init__(self, credentials: str):
        self.username = credentials.get("username")
        self.token = credentials.get("token")
        self.cloud_id = credentials.get("cloud_id")

    def create_alert(
        self,
        message: str,
        description: str,
        tags: list[str],
        extra_properties: dict,
        responder_team_id: str = None,
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

        Returns:
            Response: The response from the JiraOps API.
        """
        url = f"https://api.atlassian.com/jsm/ops/api/{self.cloud_id}/v1/alerts"
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        auth = HTTPBasicAuth(self.username, self.token)

        team_id = responder_team_id or self.DEFAULT_RESPONDER_TEAM_ID

        payload = {
            "message": message,
            "description": description,
            "responders": [{"id": team_id, "type": "team"}],
            "visibleTo": [{"id": team_id, "type": "team"}],
            "tags": tags,
            "extraProperties": extra_properties,
        }

        response = requests.post(
            url, data=json.dumps(payload), headers=headers, auth=auth
        )
        return response
