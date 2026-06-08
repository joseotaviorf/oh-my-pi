"""Sync Jira custom-field options with DAGOwnerEnum values (Jira Ops / DEI)."""

from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Sequence

import requests
from airflow.models import Variable
from requests.auth import HTTPBasicAuth

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

logger = logging.getLogger(__name__)

DEFAULT_FIELD_ID = "customfield_31231"
JIRA_OPS_AIRFLOW_VARIABLE = "JIRA_OPS_ONCALL_APIKEY"


class JiraIncidentOwnerService:
    """Keeps a Jira select custom field aligned with ``DAGOwnerEnum`` option values."""

    def __init__(
        self,
        field_id: str = DEFAULT_FIELD_ID,
    ):
        self.field_id = field_id
        self._session = requests.Session()
        self._headers = {
            "Accept": "application/json",
            "Content-Type": "application/json",
        }
        self._dag_owners_values = DAGOwnerEnum.get_available_enum_values()
        self._auth, self._base_url = self._get_authentication_parameters()
        self._context_id = self._get_context_id()

    def _get_authentication_parameters(self) -> tuple[HTTPBasicAuth, str]:
        credentials = json.loads(Variable.get(JIRA_OPS_AIRFLOW_VARIABLE))
        base_url = "https://quintoandar.atlassian.net"
        return HTTPBasicAuth(credentials["username"], credentials["token"]), base_url

    def _api_url(self, path: str) -> str:
        return f"{self._base_url}{path}"

    def _request(self, method: str, path: str, **kwargs: Any) -> requests.Response:
        response = self._session.request(
            method,
            self._api_url(path),
            headers=self._headers,
            auth=self._auth,
            timeout=kwargs.pop("timeout", 60),
            **kwargs,
        )

        logger.debug("Jira API %s %s -> %s", method, path, response.status_code)

        response.raise_for_status()

        return response

    def _get_context_id(self) -> str:
        """Return the first context id for the configured custom field."""

        path = f"/rest/api/3/field/{self.field_id}/context"
        response = self._request("GET", path)

        return response.json().get("values")[0]["id"]

    def list_field_options(self) -> Dict[str, str]:
        """Map option display value -> option id for the field context."""

        path = f"/rest/api/3/field/{self.field_id}/context/{self._context_id}/option"
        response = self._request("GET", path)

        return {
            option["value"]: option["id"]
            for option in response.json().get("values", [])
            if option.get("id") is not None
        }

    @staticmethod
    def compute_sync_diff(
        desired_values: Sequence[str],
        current_options: Dict[str, str],
    ) -> tuple[List[Dict[str, str]], List[str]]:
        """Return payloads to create and option ids to delete."""
        current_set = set(current_options.keys())
        desired_set = set(desired_values)

        new_values = sorted(desired_set - current_set)
        obsolete_ids = [
            current_options[value]
            for value in sorted(current_set - desired_set)
            if value in current_options
        ]
        create_payload = [{"value": value} for value in new_values]
        return create_payload, obsolete_ids

    def delete_option(self, context_id: str, option_id: str) -> None:
        path = (
            f"/rest/api/3/field/{self.field_id}/context/{context_id}/option/{option_id}"
        )
        self._request("DELETE", path)
        logger.info("Deleted Jira field option id=%s", option_id)

    def create_options(self, context_id: str, options: List[Dict[str, str]]) -> None:
        path = f"/rest/api/3/field/{self.field_id}/context/{context_id}/option"
        self._request(
            "POST",
            path,
            data=json.dumps({"options": options}),
        )
        logger.info("Created %s Jira field option(s).", len(options))

    def sync_incident_owner_options(self):
        """Sync incident owner options with ``DAGOwnerEnum``."""

        current_options = self.list_field_options()
        to_create, to_delete = self.compute_sync_diff(
            desired_values=self._dag_owners_values,
            current_options=current_options,
        )

        logger.info(
            "Sync plan for %s: create=%s delete=%s",
            self.field_id,
            [item["value"] for item in to_create],
            to_delete,
        )

        for option_id in to_delete:
            self.delete_option(self._context_id, option_id)

        if to_create:
            self.create_options(self._context_id, to_create)
