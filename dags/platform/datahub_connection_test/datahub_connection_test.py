import requests

import pendulum
from airflow.models import DAG
from airflow.models.param import Param
from airflow.operators.python import PythonOperator

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum


DAG_ID = "bietlejuice.datahub_connection_test"

DATAHUB_DEFAULT_URL = "http://datahub-gms.apps.data-prd.habitat.zone"

ENDPOINTS_TO_CHECK = [
    "/health",
    "/config",
    "/aspects?action=ingestProposal",
]


def test_datahub_connection(**context) -> None:
    params = context["params"]
    base_url = params["datahub_gms_url"].rstrip("/")
    token = params.get("datahub_token", "").strip()

    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    print(f"Testing DataHub GMS connectivity at: {base_url}")
    print(f"Authorization header: {'present' if token else 'not set'}")
    print("=" * 60)

    all_passed = True

    for path in ENDPOINTS_TO_CHECK:
        url = f"{base_url}{path}"
        method = "GET" if path != "/aspects?action=ingestProposal" else "POST"

        try:
            response = requests.request(
                method=method,
                url=url,
                headers=headers,
                timeout=15,
                # Empty body for the POST probe — we just want a network-level response
                json={} if method == "POST" else None,
            )
            status = response.status_code
            # 400/422 on the ingest endpoint is fine — it means we reached the server
            reachable = status < 500 or (path == "/aspects?action=ingestProposal" and status in (400, 422))
            icon = "✅" if reachable else "❌"
            print(f"{icon}  {method} {url}  →  HTTP {status}")
            if not reachable:
                all_passed = False

        except requests.exceptions.ConnectionError as exc:
            print(f"❌  {method} {url}  →  ConnectionError: {exc}")
            all_passed = False
        except requests.exceptions.Timeout:
            print(f"❌  {method} {url}  →  Timeout (15s)")
            all_passed = False
        except Exception as exc:
            print(f"❌  {method} {url}  →  Unexpected error: {exc}")
            all_passed = False

    print("=" * 60)

    if all_passed:
        print("✅  All endpoints reachable. PrivateLink connection is working.")
    else:
        raise RuntimeError(
            "One or more DataHub endpoints were unreachable. "
            "Check the logs above for details."
        )


with DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_PLATFORM,
    },
    start_date=pendulum.datetime(2024, 1, 1, tz="America/Sao_Paulo"),
    schedule_interval=None,
    catchup=False,
    tags=["platform", "datahub", "connectivity"],
    doc_md="""
## DataHub Connection Test

Validates whether the Airflow worker can reach the DataHub GMS endpoint over PrivateLink.

### Parameters

| Parameter | Description |
|---|---|
| `datahub_gms_url` | Base URL of the DataHub GMS service (default: production PrivateLink URL) |
| `datahub_token` | Optional Bearer token for authenticated endpoints |

### What it checks

1. `GET /health` — liveness probe
2. `GET /config` — config endpoint (auth-aware)
3. `POST /aspects?action=ingestProposal` — ingest endpoint (a 400/422 response still means we reached the server)

The task **fails** if any endpoint is completely unreachable (connection error or 5xx).
It **succeeds** even if DataHub returns 4xx — the goal is to confirm network-level connectivity, not API correctness.
""",
    params={
        "datahub_gms_url": Param(
            default=DATAHUB_DEFAULT_URL,
            type="string",
            description="Base URL of the DataHub GMS service",
        ),
        "datahub_token": Param(
            default="",
            type="string",
            description="Optional Bearer token for authenticated requests",
        ),
    },
) as dag:
    PythonOperator(
        task_id="test_datahub_connection",
        python_callable=test_datahub_connection,
    )
