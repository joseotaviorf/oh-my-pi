"""Minimal Airflow REST API v1 client for triggering and monitoring DAG runs."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any
from urllib.parse import urljoin

import requests


class AirflowApiError(Exception):
    def __init__(self, message: str, *, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


@dataclass
class AirflowAuth:
    token: str | None = None
    username: str | None = None
    password: str | None = None

    def headers(self) -> dict[str, str]:
        result = {"Content-Type": "application/json", "Accept": "application/json"}
        if self.token:
            result["Authorization"] = f"Bearer {self.token}"
        return result

    def auth_tuple(self) -> tuple[str, str] | None:
        if self.username and self.password:
            return (self.username, self.password)
        return None


class AirflowRestClient:
    def __init__(
        self,
        base_url: str,
        auth: AirflowAuth,
        *,
        timeout: float = 60.0,
    ) -> None:
        self.base_url = base_url.rstrip("/") + "/"
        self.auth = auth
        self.timeout = timeout
        self._session = requests.Session()

    def _api_url(self, path: str) -> str:
        normalized = path.lstrip("/")
        if not normalized.startswith("api/v1/"):
            normalized = f"api/v1/{normalized}"
        return urljoin(self.base_url, normalized)

    def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        response = self._session.request(
            method,
            self._api_url(path),
            headers=self.auth.headers(),
            auth=self.auth.auth_tuple(),
            timeout=self.timeout,
            **kwargs,
        )
        if response.status_code >= 400:
            detail = response.text[:500]
            raise AirflowApiError(
                f"{method} {path} failed ({response.status_code}): {detail}",
                status_code=response.status_code,
            )
        if response.status_code == 204 or not response.content:
            return None
        return response.json()

    def list_dags_by_tag(self, tag: str) -> list[dict[str, Any]]:
        dags: list[dict[str, Any]] = []
        offset = 0
        limit = 100
        while True:
            payload = self._request(
                "GET",
                "dags",
                params={
                    "tags": tag,
                    "limit": limit,
                    "offset": offset,
                    "only_active": True,
                },
            )
            batch = payload.get("dags", [])
            dags.extend(batch)
            total = payload.get("total_entries", len(dags))
            offset += limit
            if offset >= total or not batch:
                break
        return dags

    def get_dag(self, dag_id: str) -> dict[str, Any]:
        return self._request("GET", f"dags/{dag_id}")

    def set_dag_paused(self, dag_id: str, *, is_paused: bool) -> dict[str, Any]:
        return self._request(
            "PATCH",
            f"dags/{dag_id}",
            params={"update_mask": "is_paused"},
            json={"is_paused": is_paused},
        )

    def ensure_dag_unpaused(self, dag_id: str) -> bool:
        """Unpause if paused. Returns True when a PATCH was sent."""
        dag = self.get_dag(dag_id)
        if not dag.get("is_paused"):
            return False
        self.set_dag_paused(dag_id, is_paused=False)
        return True

    def trigger_dag_run(self, dag_id: str, conf: dict[str, Any]) -> dict[str, Any]:
        return self._request(
            "POST",
            f"dags/{dag_id}/dagRuns",
            json={"conf": conf},
        )

    def get_dag_run(self, dag_id: str, dag_run_id: str) -> dict[str, Any]:
        return self._request("GET", f"dags/{dag_id}/dagRuns/{dag_run_id}")

    def list_dag_runs(
        self,
        dag_id: str,
        *,
        states: list[str] | None = None,
        limit: int = 25,
        order_by: str = "-start_date",
    ) -> list[dict[str, Any]]:
        params: list[tuple[str, str | int]] = [
            ("limit", limit),
            ("order_by", order_by),
        ]
        if states:
            for state in states:
                params.append(("state", state))
        payload = self._request(
            "GET",
            f"dags/{dag_id}/dagRuns",
            params=params,
        )
        return payload.get("dag_runs", [])

    def list_task_instances(self, dag_id: str, dag_run_id: str) -> list[dict[str, Any]]:
        payload = self._request(
            "GET",
            f"dags/{dag_id}/dagRuns/{dag_run_id}/taskInstances",
        )
        return payload.get("task_instances", [])

    def get_task_log(
        self,
        dag_id: str,
        dag_run_id: str,
        task_id: str,
        try_number: int,
    ) -> str:
        payload = self._request(
            "GET",
            f"dags/{dag_id}/dagRuns/{dag_run_id}/taskInstances/{task_id}/logs/{try_number}",
        )
        if isinstance(payload, str):
            return payload
        if not isinstance(payload, dict):
            return ""

        content = payload.get("content", "")
        continuation = payload.get("continuation_token")
        while continuation:
            next_payload = self._request(
                "GET",
                f"dags/{dag_id}/dagRuns/{dag_run_id}/taskInstances/{task_id}/logs/{try_number}",
                params={"token": continuation},
            )
            if not isinstance(next_payload, dict):
                break
            content += next_payload.get("content", "")
            continuation = next_payload.get("continuation_token")
        return content
