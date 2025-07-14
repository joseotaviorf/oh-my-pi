from datetime import datetime
import requests
from quintoandar_logger import QuintoAndarLogger
from requests import Response

logger = QuintoAndarLogger("OpsgenieCallback")


class OpsgenieClient:
    """Opsgenie client class to send alerts from airflow dags to Opsgenie"""

    def __init__(self, api_key: str, integration_name: str):
        self.api_key = api_key
        self.integration_name = integration_name

    def create_incident(
        self,
        resource_name: str,
        summary_message: str,
        full_description: str,
        metric_labels: dict = None,
        resource_labels: dict = None,
        issue_summary: str = "",
    ) -> Response:
        """
        Create an incident in Opsgenie using the provided payload.

        Args:
            resource_name (str): The name of the resource.
            summary_message (str): The summary message for the incident.
            full_description (str): The full description of the incident.
            metric_labels (dict): Labels for the metric.
            resource_labels (dict): Labels for the resource.
            issue_summary (str): Summary of the issue.

        Returns:
            Response: The response from the Opsgenie API.
        """
        url = f"https://api.opsgenie.com/v1/json/{self.integration_name}?apiKey={self.api_key}"
        headers = {"Content-Type": "application/json"}
        payload = {
            "incident": {
                "resource_name": resource_name,
                "state": "open",
                "started_at": datetime.timestamp(datetime.now()),
                "summary": summary_message,
                "description": full_description,
                "metric": {"labels": metric_labels or {}},
                "resource": {"labels": resource_labels or {}},
            },
            "fields": {"summary": issue_summary},
            "version": 1.1,
        }

        response = requests.post(url, json=payload, headers=headers)
        return response
