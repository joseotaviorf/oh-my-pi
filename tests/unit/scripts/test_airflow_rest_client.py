from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import MagicMock

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from scripts.airflow_rest_client import AirflowAuth, AirflowRestClient  # noqa: E402


def _client() -> AirflowRestClient:
    return AirflowRestClient("https://airflow.example/", AirflowAuth(token="token"))


class TestTriggerDagRun:
    def test_conf_only_body(self) -> None:
        client = _client()
        client._request = MagicMock(return_value={"dag_run_id": "manual__test"})

        client.trigger_dag_run("bietlejuice.foo", {"run_type": "test_run"})

        client._request.assert_called_once_with(
            "POST",
            "dags/bietlejuice.foo/dagRuns",
            json={"conf": {"run_type": "test_run"}},
        )

    def test_includes_custom_dag_run_id_and_logical_date(self) -> None:
        client = _client()
        client._request = MagicMock(return_value={"dag_run_id": "val__20260613143022_a1b2"})

        client.trigger_dag_run(
            "bietlejuice.foo__validation",
            {"run_type": "test_run"},
            dag_run_id="val__20260613143022_a1b2",
            logical_date="2026-06-13T14:30:22+00:00",
        )

        client._request.assert_called_once_with(
            "POST",
            "dags/bietlejuice.foo__validation/dagRuns",
            json={
                "conf": {"run_type": "test_run"},
                "dag_run_id": "val__20260613143022_a1b2",
                "logical_date": "2026-06-13T14:30:22+00:00",
            },
        )
