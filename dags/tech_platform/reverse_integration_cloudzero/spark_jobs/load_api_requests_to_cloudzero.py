"""
Spark job that queries Prometheus (via Grafana datasource) for API request counts and sends them to CloudZero.

Uses Grafana's datasource proxy to run a PromQL instant query (Grafana backend can be Thanos/Prometheus).
Fetches the number of requests per app, then posts each series to CloudZero with a configurable dimension (default custom:API; create Custom Dimension "API" in CloudZero).
"""

from __future__ import annotations

import json
import logging
import os
from argparse import ArgumentParser
from datetime import datetime, timezone
from urllib.parse import quote

import requests
from quintoandar_logger import QuintoAndarLogger
from requests import RequestException
from requests.adapters import HTTPAdapter, Retry

from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.base.validation.spark_args import add_validation_target_args

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_api_requests_to_cloudzero"

# Default Grafana base URL (prod)
DEFAULT_GRAFANA_URL = "https://grafana.apps.shared-prd.habitat.zone"
# Default Grafana datasource name (Prometheus/Thanos); auth is via Grafana service account
DEFAULT_GRAFANA_DATASOURCE_NAME = "metrics-prod"
# Default PromQL (instant): total requests in the last 24h grouped by label 'app'
DEFAULT_PROMQL = "sum(increase(http_server_requests_seconds_count[24h])) by (app)"
# Query step for range queries: always automatic (~110 points max per day)
DEFAULT_DIMENSION_LABEL = "app"
# CloudZero dimension key in associated_cost. CZ:K8s:Workload is not accepted by Unit Cost Telemetry API in many accounts;
# use custom:API (create Custom Dimension "API" in CloudZero) for reliable behavior.
DEFAULT_CLOUDZERO_DIMENSION_KEY = "custom:API"
CLOUDZERO_METRIC_NAME = "quintoandar_api_requests_count"
# Max points for "auto" step (Prometheus-style)
AUTO_STEP_MAX_POINTS = 110

logging.getLogger("py4j").setLevel(logging.INFO)
logger = QuintoAndarLogger(JOB_NAME)


def _get_secret(dbutils, key: str, env_key: str = None, default: str = None) -> str:
    """Read from Databricks secret or env, with optional default."""
    try:
        if dbutils is not None:
            return dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=key).strip()
    except Exception:
        pass
    env_key = env_key or key
    val = os.environ.get(env_key, "").strip()
    return val if val else (default or "")


def get_grafana_url(dbutils) -> str:
    """Grafana base URL. From secret GRAFANA_URL, env, or default (prod)."""
    url = _get_secret(dbutils, "GRAFANA_URL", default="")
    if not url:
        return DEFAULT_GRAFANA_URL
    return url.rstrip("/")


def get_grafana_datasource_name(dbutils) -> str:
    """Grafana datasource name. From secret GRAFANA_DATASOURCE_NAME, env, or default (metrics-prod)."""
    name = _get_secret(dbutils, "GRAFANA_DATASOURCE_NAME", default="")
    return name if name else DEFAULT_GRAFANA_DATASOURCE_NAME


def get_grafana_datasource_uid(dbutils) -> str:
    """Grafana datasource UID. From secret GRAFANA_DATASOURCE_UID or resolved from name via Grafana API."""
    return _get_secret(dbutils, "GRAFANA_DATASOURCE_UID", default="")


def get_grafana_api_token(dbutils) -> str:
    """Grafana service account token for API/datasource proxy auth. From secret GRAFANA_API_TOKEN or env."""
    return _get_secret(dbutils, "GRAFANA_API_TOKEN", default="")


def resolve_datasource_uid_by_name(
    grafana_base_url: str,
    datasource_name: str,
    api_token: str,
    timeout_seconds: int = 30,
) -> str:
    """
    Resolve Grafana datasource UID from name via GET /api/datasources/name/:name.
    Requires Grafana API authentication (e.g. service account token).
    """
    if not api_token:
        raise RuntimeError(
            "GRAFANA_API_TOKEN (service account token) is required when using datasource name; "
            "or set GRAFANA_DATASOURCE_UID explicitly"
        )
    url = f"{grafana_base_url}/api/datasources/name/{quote(datasource_name, safe='')}"
    headers = {"Authorization": f"Bearer {api_token}"}
    session = requests.Session()
    retries = Retry(total=2, backoff_factor=1, status_forcelist=[502, 503, 504])
    session.mount("https://", HTTPAdapter(max_retries=retries))
    session.mount("http://", HTTPAdapter(max_retries=retries))
    logger.info(f"m=resolve_datasource_uid_by_name, name={datasource_name}")
    response = session.get(url, headers=headers, timeout=timeout_seconds)
    response.raise_for_status()
    data = response.json()
    uid = data.get("uid")
    if not uid:
        raise RuntimeError(
            f"Grafana datasource '{datasource_name}' response did not contain 'uid': {data}"
        )
    logger.info(f"m=resolve_datasource_uid_by_name, uid={uid}")
    return uid


def get_promql_query(dbutils) -> str:
    """PromQL for request count per API. From secret PROMETHEUS_REQUESTS_QUERY or default."""
    try:
        return dbutils.secrets.get(
            scope=DATABRICKS_SCOPE, key="PROMETHEUS_REQUESTS_QUERY"
        ).strip()
    except Exception:
        pass
    return os.environ.get("PROMETHEUS_REQUESTS_QUERY", DEFAULT_PROMQL)


def get_dimension_label(dbutils) -> str:
    """Label name used as dimension (e.g. app, api, uri). From secret or default."""
    try:
        return dbutils.secrets.get(
            scope=DATABRICKS_SCOPE, key="PROMETHEUS_REQUESTS_DIMENSION_LABEL"
        ).strip()
    except Exception:
        pass
    return os.environ.get(
        "PROMETHEUS_REQUESTS_DIMENSION_LABEL", DEFAULT_DIMENSION_LABEL
    )


def get_cloudzero_dimension_key(dbutils) -> str:
    """CloudZero dimension key in associated_cost (e.g. custom:API, K8s:Workload). From secret or default."""
    try:
        val = dbutils.secrets.get(
            scope=DATABRICKS_SCOPE, key="CLOUDZERO_DIMENSION_KEY"
        ).strip()
        if val:
            return val
    except Exception:
        pass
    return os.environ.get("CLOUDZERO_DIMENSION_KEY", DEFAULT_CLOUDZERO_DIMENSION_KEY)


def auto_step_seconds(range_seconds: int) -> int:
    """Step in seconds for automatic resolution (~AUTO_STEP_MAX_POINTS points per range)."""
    return max(60, range_seconds // AUTO_STEP_MAX_POINTS)


def promql_duration_from_step_seconds(step_sec: int) -> str:
    """PromQL range duration from step (e.g. 3600 -> '1h', 900 -> '15m')."""
    if step_sec >= 3600:
        return f"{step_sec // 3600}h"
    if step_sec >= 60:
        return f"{step_sec // 60}m"
    return f"{step_sec}s"


def query_prometheus_via_grafana(
    grafana_base_url: str,
    datasource_uid: str,
    query: str,
    evaluation_ts: datetime,
    api_token: str = "",
    timeout_seconds: int = 60,
) -> list:
    """
    Run a Prometheus instant query via Grafana datasource proxy.

    Uses GET /api/datasources/proxy/uid/{uid}/api/v1/query (Grafana proxies to
    the configured Prometheus/Thanos backend).

    :param grafana_base_url: Grafana base URL (e.g. https://grafana.company.com)
    :param datasource_uid: UID of the Prometheus/Thanos datasource in Grafana
    :param query: PromQL expression
    :param evaluation_ts: Time for the instant query (end of day recommended)
    :param api_token: Optional Grafana API token for Authorization header
    :param timeout_seconds: Request timeout
    :return: List of (dict of labels, float value)
    """
    url = f"{grafana_base_url}/api/datasources/proxy/uid/{datasource_uid}/api/v1/query"
    params = {
        "query": query,
        "time": int(evaluation_ts.timestamp()),
        "timeout": f"{timeout_seconds}s",
        "dedup": "true",
        "partial_response": "false",
    }
    headers = {}
    if api_token:
        headers["Authorization"] = f"Bearer {api_token}"

    session = requests.Session()
    retries = Retry(total=3, backoff_factor=1, status_forcelist=[502, 503, 504])
    session.mount("https://", HTTPAdapter(max_retries=retries))
    session.mount("http://", HTTPAdapter(max_retries=retries))

    logger.info(f"m=query_prometheus_via_grafana, url={url}, query={query}")
    response = session.get(
        url, params=params, headers=headers or None, timeout=timeout_seconds
    )
    response.raise_for_status()
    data = response.json()

    if data.get("status") != "success":
        raise RuntimeError(f"Prometheus API error: {data.get('error', data)}")

    result = data.get("data", {}).get("result", [])
    out = []
    for item in result:
        metric = item.get("metric", {})
        raw = item.get("value")
        if raw is None:
            continue
        try:
            val = float(raw[1])
        except (IndexError, TypeError, ValueError):
            continue
        out.append((dict(metric), val))
    return out


def query_range_via_grafana(
    grafana_base_url: str,
    datasource_uid: str,
    query: str,
    start_ts: datetime,
    end_ts: datetime,
    step_seconds: int,
    api_token: str = "",
    timeout_seconds: int = 120,
) -> list:
    """
    Run a Prometheus range query via Grafana datasource proxy; aggregate to one value per series (sum).

    Uses GET /api/datasources/proxy/uid/{uid}/api/v1/query_range.
    Returns list of (metric_labels, aggregated_value) by summing values per series.
    """
    url = f"{grafana_base_url}/api/datasources/proxy/uid/{datasource_uid}/api/v1/query_range"
    params = {
        "query": query,
        "start": int(start_ts.timestamp()),
        "end": int(end_ts.timestamp()),
        "step": step_seconds,
        "timeout": f"{timeout_seconds}s",
        "dedup": "true",
        "partial_response": "false",
    }
    headers = {}
    if api_token:
        headers["Authorization"] = f"Bearer {api_token}"

    session = requests.Session()
    retries = Retry(total=3, backoff_factor=1, status_forcelist=[502, 503, 504])
    session.mount("https://", HTTPAdapter(max_retries=retries))
    session.mount("http://", HTTPAdapter(max_retries=retries))

    logger.info(
        f"m=query_range_via_grafana, url={url}, query={query}, step={step_seconds}s"
    )
    response = session.get(
        url, params=params, headers=headers or None, timeout=timeout_seconds
    )
    response.raise_for_status()
    data = response.json()

    if data.get("status") != "success":
        raise RuntimeError(f"Prometheus API error: {data.get('error', data)}")

    result = data.get("data", {}).get("result", [])
    out = []
    for item in result:
        metric = dict(item.get("metric", {}))
        values = item.get("values", [])
        total = 0.0
        for v in values:
            try:
                total += float(v[1])
            except (IndexError, TypeError, ValueError):
                continue
        out.append((metric, total))
    return out


def send_api_requests_to_cloudzero(
    records: list,
    execution_date: str,
    cloudzero_token: str,
    dimension_label: str,
    dimension_key: str,
) -> None:
    """
    Send API request counts to CloudZero (one record per dimension value).

    :param records: List of (metric_labels_dict, value) from Prometheus
    :param execution_date: Date of the data (YYYY-MM-DD)
    :param cloudzero_token: CloudZero API token
    :param dimension_label: Prometheus label for the dimension value (e.g. app, api, uri)
    :param dimension_key: CloudZero key in associated_cost (e.g. custom:API, K8s:Workload)
    """
    # Build records with associated_cost for dimension
    payload_records = []
    for labels, value in records:
        elem = (
            labels.get(dimension_label)
            or labels.get("app")
            or labels.get("uri")
            or "unknown"
        )
        payload_records.append(
            {
                "granularity": "DAILY",
                "timestamp": execution_date,
                "value": int(round(value)),
                "associated_cost": {dimension_key: str(elem)},
            }
        )

    if not payload_records:
        logger.info("m=send_api_requests_to_cloudzero, no_records_skipping")
        return

    payload = {"records": payload_records}
    url = (
        "https://api.cloudzero.com/unit-cost/v1/telemetry/metric/"
        f"{CLOUDZERO_METRIC_NAME}/replace"
    )
    headers = {
        "Authorization": cloudzero_token,
        "content-type": "application/json",
    }

    session = requests.Session()
    retries = Retry(total=5, backoff_factor=1, status_forcelist=[502, 503, 504])
    session.mount("https://", HTTPAdapter(max_retries=retries))
    session.verify = True
    session.trust_env = False

    try:
        logger.info(
            f"m=send_api_requests_to_cloudzero, sending_records={len(payload_records)}"
        )
        response = session.post(url, headers=headers, json=payload)
        response.raise_for_status()
        logger.info(
            f"m=send_api_requests_to_cloudzero, success, status_code={response.status_code}"
        )
    except RequestException as e:
        if e.response is not None:
            logger.error(
                f"m=send_api_requests_to_cloudzero, error, status_code={e.response.status_code}, "
                f"error_message={e.response.text}, records_count={len(payload_records)}"
            )
        else:
            logger.error(
                f"m=send_api_requests_to_cloudzero, error={e}, records_count={len(payload_records)}"
            )
        raise


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("execution_date", help="Execution date in YYYY-MM-DD format")
    add_validation_target_args(parser)

    args = parser.parse_args()
    environment = args.environment
    execution_date = args.execution_date

    logger.info(
        f"m=__main__, environment={environment}, execution_date={execution_date}"
    )

    try:
        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils() if base_dbutils else None
        if dbutils is None:
            raise RuntimeError("Databricks dbutils not available")

        # CloudZero token
        logger.info("m=__main__, Getting credentials from Databricks secrets")
        json_credentials = dbutils.secrets.get(
            scope=DATABRICKS_SCOPE, key="CLOUDZERO_API_TOKEN"
        )
        try:
            credentials_dict = json.loads(json_credentials)
        except Exception as e:
            logger.error(f"m=__main__, error_parsing_json_credentials, error={e}")
            raise RuntimeError(f"Error parsing CLOUDZERO_API_TOKEN secret as JSON: {e}")
        if not isinstance(credentials_dict, dict) or "token" not in credentials_dict:
            raise RuntimeError(
                "CLOUDZERO_API_TOKEN secret does not contain a 'token' key."
            )
        cloudzero_token = credentials_dict["token"]

        grafana_url = get_grafana_url(dbutils)
        grafana_token = get_grafana_api_token(dbutils)
        datasource_uid = get_grafana_datasource_uid(dbutils)
        if not datasource_uid:
            datasource_name = get_grafana_datasource_name(dbutils)
            datasource_uid = resolve_datasource_uid_by_name(
                grafana_url, datasource_name, grafana_token
            )
        dimension_label = get_dimension_label(dbutils)
        dimension_key = get_cloudzero_dimension_key(dbutils)

        # Day range in UTC so Prometheus/Thanos evaluate at the correct time
        start_ts = datetime.strptime(
            execution_date + " 00:00:00", "%Y-%m-%d %H:%M:%S"
        ).replace(tzinfo=timezone.utc)
        end_ts = datetime.strptime(
            execution_date + " 23:59:59", "%Y-%m-%d %H:%M:%S"
        ).replace(tzinfo=timezone.utc)
        range_seconds = int((end_ts - start_ts).total_seconds()) + 1
        step_seconds = auto_step_seconds(range_seconds)
        step_dur = promql_duration_from_step_seconds(step_seconds)
        # Range PromQL: increase per step, then we sum all points per series
        range_promql = f"sum(increase(http_server_requests_seconds_count[{step_dur}])) by ({dimension_label})"

        records = query_range_via_grafana(
            grafana_url,
            datasource_uid,
            range_promql,
            start_ts,
            end_ts,
            step_seconds,
            api_token=grafana_token,
        )
        logger.info(
            f"m=__main__, prometheus_series_count={len(records)}, step=auto({step_seconds}s)"
        )

        send_api_requests_to_cloudzero(
            records, execution_date, cloudzero_token, dimension_label, dimension_key
        )
        logger.info(f"m=__main__, success, series_sent={len(records)}")

    except Exception as e:
        logger.error(f"m=__main__, error={e}")
        raise RuntimeError(f"Error in {JOB_NAME}: {e}")
