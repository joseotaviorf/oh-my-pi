import json
import requests
from requests.auth import HTTPBasicAuth

from quintoandar_logger import QuintoAndarLogger


logger = QuintoAndarLogger("JiraOpsClient")


class JiraOpsClient:
    def __init__(self, credentials: str):
        self.username = credentials.get("username")
        self.token = credentials.get("token")
        self.cloud_id = credentials.get("cloud_id")

    def create_alert(
        self, message: str, description: str, tags: list[str]
    ) -> requests.Response:
        """
        Create an alert in JiraOps using the provided payload.

        Args:
            message (str): The message for the alert.
            description (str): The description of the alert.
            tags (list[str]): List of tags to be associated with the alert.

        Returns:
            Response: The response from the JiraOps API.
        """
        url = f"https://api.atlassian.com/jsm/ops/api/{self.cloud_id}/v1/alerts"
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        auth = HTTPBasicAuth(self.username, self.token)

        # analytics engineering team id: og-7c6d473a-9c80-4513-af76-9f2861cf966a
        # it is necessary to explicitly declare the team as visible and responder of the alert
        payload = {
            "message": message,
            "description": description,
            "responders": [
                {"id": "og-7c6d473a-9c80-4513-af76-9f2861cf966a", "type": "team"}
            ],
            "visibleTo": [
                {"id": "og-7c6d473a-9c80-4513-af76-9f2861cf966a", "type": "team"}
            ],
            "tags": tags,
        }

        response = requests.post(
            url, data=json.dumps(payload), headers=headers, auth=auth
        )
        return response
