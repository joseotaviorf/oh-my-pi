"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs
"""

from __future__ import annotations

import json
import logging
import os
import re
from datetime import datetime, timedelta
from urllib.parse import parse_qs, urlparse
from zoneinfo import ZoneInfo

import pendulum
import requests
from airflow import DAG
from airflow.models import DagModel, Variable
from airflow.operators.python import PythonOperator
from airflow.utils.db import provide_session
from requests.auth import HTTPBasicAuth

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.configuration_service import ConfigurationService

logger = logging.getLogger(__name__)

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
SP_TZ = ZoneInfo("America/Sao_Paulo")

JIRA_OPS_SCHEDULE_ID = "9e63f54a-de9c-4e0d-bf48-75c95a28450d"
DEI_JIRA_PROJECT = "DEI"
DEI_BOARD_URL = (
    "https://quintoandar.atlassian.net/jira/software/projects/DEI/boards/437"
)
JIRA_SERVER = "https://quintoandar.atlassian.net"
JIRA_OPS_API_BASE = "https://api.atlassian.com/jsm/ops/api"
# DAGOwnerEnum-aligned Incident Owner. customfield_12078 is the deactivated legacy field.
INCIDENT_OWNER_FIELD = "customfield_31231"
WONKA_DAG_ID_PREFIX = "quintoml.wonka."

_OWNER_DISPLAY_NAME_MAP = {
    "Data ForRent": "Data For Rent",
    "Data ForSale": "Data For Sale",
    "Data SS": "Data S&S",
    "Data Fintech": "Data Fintech",
    "Data Rede": "Data 3P Partners",
    "Data 3P Partners": "Data 3P Partners",
    "Data Growth": "Data Growth",
    "Data Life Cycle": "Data Life Cycle",
    "Data Platform": "Data Serving",
    "Data Governance": "Data Governance",
    "MLOps": "MLOps",
    "MLOps Team": "MLOps",
    "Data Primitives": "Data Primitives",
    "Data CDP": "Data Primitives",
    "Data Agents": "Data Agents",
    "Data People": "Data People",
    "Data Conversational XP": "Data Conversational XP",
    "Tech Platform Cyber Security": "Tech Platform Cyber Security",
    "Tech Platform Dev Foundation": "Tech Platform Dev Foundation",
    "Tech Platform Workforce Productivity": "Tech Platform Workforce Productivity",
    "Data Planning and Performance": "Data Planning and Performance",
    "Tech Platform Engineering Productivity": "Tech Platform Engineering Productivity",
    "Tech Platform Enterprise Engineering": "Tech Platform Enterprise Engineering",
    "QCX": "QCX",
    "Data DS Pricing": "Data DS Pricing",
    "Search": "MLOps",
}

# Airflow owners that are not DAGOwnerEnum values but must land on a 31231 option.
_AIRFLOW_OWNER_TO_INCIDENT_OWNER = {
    "Search": "MLOps",
    "MLOps Team": "MLOps",
}

SOURCE_RUNTIME_ANOMALY = "Runtime anomaly"
SOURCE_AIRFLOW_ERROR = "Airflow error"
SOURCE_UNKNOWN = "Unknown"
RUBINHO_ALIAS_PREFIX = "dag-runtime-"


def _parse_rfc3339(datetime_str: str) -> datetime:
    """Parse an RFC 3339 datetime string with or without fractional seconds."""
    try:
        return datetime.strptime(datetime_str, "%Y-%m-%dT%H:%M:%S.%f%z")
    except ValueError:
        return datetime.strptime(datetime_str, "%Y-%m-%dT%H:%M:%S%z")


def _parse_optional_datetime(value) -> datetime | None:
    """Parse Jira / Jira Ops timestamps (RFC 3339 strings or Unix epoch)."""
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=SP_TZ)
        return value
    if isinstance(value, (int, float)):
        ts = value / 1000.0 if value > 1e12 else float(value)
        return datetime.fromtimestamp(ts, tz=SP_TZ)
    if not isinstance(value, str):
        return None
    try:
        return _parse_rfc3339(value)
    except ValueError:
        return None


def _normalize_tags(tags) -> list[str]:
    """Coerce Jira Ops ``tags`` (list or string) into a list of strings."""
    if not tags:
        return []
    if isinstance(tags, str):
        return [tags]
    return [str(tag) for tag in tags if tag]


def _classify_incident_source(
    message: str,
    tags: list[str] | None = None,
    alias: str | None = None,
) -> str:
    """Classify a Jira Ops alert as Rubinho slowness, Airflow failure, or unknown."""
    if alias and str(alias).startswith(RUBINHO_ALIAS_PREFIX):
        return SOURCE_RUNTIME_ANOMALY
    msg = (message or "").lower()
    tag_blob = " ".join(_normalize_tags(tags)).lower()
    if "runtime anomaly" in msg or "runtime anomaly" in tag_blob:
        return SOURCE_RUNTIME_ANOMALY
    if (
        msg.startswith("dag:")
        or ("dag:" in msg and "task:" in msg)
        or "task failed" in tag_blob
        or "dag failed" in tag_blob
    ):
        return SOURCE_AIRFLOW_ERROR
    return SOURCE_UNKNOWN


def _resolve_now_sp(load_start_date: str | None) -> datetime:
    """Return the notification anchor time (09:00 SP) for production runs or backtests."""
    if not load_start_date:
        return datetime.now(tz=SP_TZ)
    try:
        parsed = datetime.strptime(load_start_date.strip(), "%Y-%m-%d")
    except ValueError as exc:
        raise ValueError(
            f"Invalid load_start_date '{load_start_date}'; expected YYYY-MM-DD"
        ) from exc
    return parsed.replace(hour=9, minute=0, second=0, microsecond=0, tzinfo=SP_TZ)


def _clean_dag_owner(raw_owners: str) -> str:
    """Strip the 'airflow' pseudo-owner injected by the Airflow framework."""
    return raw_owners.replace("airflow, ", "").replace(" ,airflow", "").strip()


def _incident_owner_from_dag(dag_id: str, raw_owner: str | None) -> str:
    """Resolve the Jira Incident Owner (customfield_31231) for a DAG.

    Wonka DAGs always map to MLOps. Other DAGs use the Airflow owner, remapped
    when that owner is not a DAGOwnerEnum / 31231 option.
    """
    if dag_id.startswith(WONKA_DAG_ID_PREFIX):
        return "MLOps"
    if not raw_owner:
        return "AE All"
    return _AIRFLOW_OWNER_TO_INCIDENT_OWNER.get(raw_owner, raw_owner)


def _display_owner_name(owner: str) -> str:
    """Map a DAGOwnerEnum value to the label used in the on-call notification."""
    return _OWNER_DISPLAY_NAME_MAP.get(owner, owner)


def _fetch_dei_issues(
    jira_auth: HTTPBasicAuth, dt_start: str, dt_end: str
) -> list[dict]:
    """Fetch DEI Jira issues created during the on-call window (D-1 21:00 → D 09:00)."""
    url = f"{JIRA_SERVER}/rest/api/3/search/jql"
    jql = (
        f'created >= "{dt_start} 21:00" AND created <= "{dt_end} 09:00"'
        f' AND project = "{DEI_JIRA_PROJECT}"'
    )
    headers = {"Accept": "application/json", "Content-Type": "application/json"}

    all_issues = []
    next_page_token: str | None = None
    max_results = 100

    while True:
        payload: dict = {
            "jql": jql,
            "fields": ["id", "key", "summary", "created", INCIDENT_OWNER_FIELD],
            "maxResults": max_results,
        }
        if next_page_token:
            payload["nextPageToken"] = next_page_token

        resp = requests.post(url, json=payload, headers=headers, auth=jira_auth)
        resp.raise_for_status()
        data = resp.json()

        for issue in data.get("issues", []):
            owner_field = issue["fields"].get(INCIDENT_OWNER_FIELD)
            incident_owner = owner_field.get("value") if owner_field else None
            all_issues.append(
                {
                    "id": issue["id"],
                    "key": issue["key"],
                    "summary": issue["fields"]["summary"],
                    "created": issue["fields"]["created"],
                    "incident_owner": incident_owner,
                }
            )

        if data.get("isLast", True) or not data.get("issues"):
            break
        next_page_token = data.get("nextPageToken")
        if not next_page_token:
            logger.warning(
                "isLast=False but nextPageToken missing — stopping pagination"
            )
            break

    return all_issues


def _resolve_issue_owners(
    issues: list[dict],
    dag_owner_map: dict[str, str],
    jira_auth: HTTPBasicAuth,
) -> list[dict]:
    """
    Resolve missing owners via the Airflow DagModel lookup and write them back to Jira.

    Issues where incident_owner (customfield_31231) is None or 'AE All' are
    resolved by treating the issue summary as a DAG ID and looking it up in
    the dag_owner_map (derived from the Airflow DagModel). The value written
    back to Jira is the DAGOwnerEnum string; the notification may use a
    friendlier label from _OWNER_DISPLAY_NAME_MAP.
    """
    issues_to_update: dict[str, str] = {}

    for idx, issue in enumerate(issues):
        if issue["incident_owner"] in (None, "AE All"):
            raw_owner = dag_owner_map.get(issue["summary"])
            jira_owner = _incident_owner_from_dag(issue["summary"], raw_owner)
            display_owner = _display_owner_name(jira_owner)
            issues[idx]["owner"] = display_owner
            if jira_owner != "AE All":
                issues_to_update[issue["key"]] = jira_owner
        else:
            issues[idx]["owner"] = _display_owner_name(issue["incident_owner"])

    headers = {"Accept": "application/json", "Content-Type": "application/json"}
    problematic = []
    for issue_key, owner in issues_to_update.items():
        try:
            url = f"{JIRA_SERVER}/rest/api/3/issue/{issue_key}"
            payload = {"fields": {INCIDENT_OWNER_FIELD: {"value": owner}}}
            resp = requests.put(url, json=payload, headers=headers, auth=jira_auth)
            resp.raise_for_status()
            logger.info(
                "updated issue=%s, owner=%s, status=%s",
                issue_key,
                owner,
                resp.status_code,
            )
        except Exception as exc:
            logger.warning("failed to update %s: %s", issue_key, exc)
            problematic.append(issue_key)

    if problematic:
        logger.warning("Could not update owners for: %s", problematic)

    return issues


def _get_schedule_timeline(
    cloud_id: str,
    jira_ops_auth: HTTPBasicAuth,
    shift_date: str,
    interval: int = 1,
    time_suffix: str = "T21:00:00Z",
) -> dict:
    """Fetch the on-call schedule timeline for a given date from Jira Ops.

    time_suffix controls the UTC start of the query window:
    - "T21:00:00Z" (default): 18:00 BRT on shift_date, captures 21:00 BRT overnight shifts.
    - "T00:00:00Z": 21:00 BRT on shift_date-1, captures holiday exception shifts at 09:00 BRT.
    - "T12:00:00Z": 09:00 BRT on shift_date, captures the Sunday exceptional 09:00-12:00 shift.
    """
    url = (
        f"{JIRA_OPS_API_BASE}/{cloud_id}/v1/schedules/{JIRA_OPS_SCHEDULE_ID}/timeline"
        f"?expand=base,forwarding,override&interval={interval}&intervalUnit=days"
        f"&date={shift_date}{time_suffix}"
    )
    resp = requests.get(url, headers={"Accept": "application/json"}, auth=jira_ops_auth)
    resp.raise_for_status()
    return resp.json()


def _get_user_display(account_id: str, jira_ops_auth: HTTPBasicAuth) -> dict:
    """Resolve a Jira account ID to display name and email address."""
    if not account_id:
        return {"displayName": "Deleted User", "emailAddress": "Deleted User"}
    resp = requests.get(
        f"{JIRA_SERVER}/rest/api/2/user",
        params={"accountId": account_id},
        headers={"Accept": "application/json"},
        auth=jira_ops_auth,
    )
    resp.raise_for_status()
    data = resp.json()
    return {
        "displayName": data.get("displayName") or account_id or "Unknown",
        "emailAddress": data.get("emailAddress") or "",
    }


def _is_sunday_morning_report(anchor: datetime) -> bool:
    """True when the 09:00 report runs on Sunday (exceptional 09:00-12:00 shift)."""
    return anchor.weekday() == 6


def _should_include_oncall_period(
    start_dt: datetime,
    *,
    periods_length_exception: int,
    sunday_morning: bool,
) -> bool:
    """Decide whether a Jira Ops timeline period is the shift this report should attribute.

    - Sunday morning / holiday exception: include the 09:00 BRT day shift.
    - Normal overnight shifts: include the 21:00 BRT start.
    """
    if sunday_morning or periods_length_exception == 1:
        return start_dt.hour == 9
    return start_dt.hour == 21


def _dedupe_recipients(recipients: list[dict]) -> list[dict]:
    """Preserve first-seen order while dropping duplicate emails."""
    return list({r["emailAddress"]: r for r in recipients}.values())


def _recipients_from_rotations(
    rotations: list[dict],
    jira_ops_auth: HTTPBasicAuth,
    *,
    periods_length_exception: int,
    sunday_morning: bool,
) -> list[dict]:
    """Resolve timeline periods into notification recipients using the shift hour rules."""
    recipients: list[dict] = []
    for rotation in rotations:
        rotation_name = rotation.get("name", "")
        for period in rotation.get("periods", []):
            start_dt = _parse_rfc3339(period["startDate"]).astimezone(SP_TZ)
            account_id = (period.get("responder") or {}).get("id")
            user = _get_user_display(account_id, jira_ops_auth)
            # endDate is logged raw: Jira Ops emits non-RFC-3339 values such as "T24:00:00Z".
            logger.info(
                "rotation=%s, responder=%s, hour=%s, start=%s, end_raw=%s, type=%s",
                rotation_name,
                user["displayName"],
                start_dt.hour,
                start_dt.isoformat(),
                period.get("endDate"),
                period.get("type"),
            )

            include = _should_include_oncall_period(
                start_dt,
                periods_length_exception=periods_length_exception,
                sunday_morning=sunday_morning,
            )

            if include:
                recipients.append(user)
                logger.info("→ included")

    return _dedupe_recipients(recipients)


def _get_oncall_recipients(
    cloud_id: str,
    jira_ops_auth: HTTPBasicAuth,
    now_sp: datetime | None = None,
) -> tuple[list[dict], int]:
    """
    Determine the on-call engineer(s) for the previous shift.

    Returns (recipients, periods_length_exception) where:
    - recipients: list of {displayName, emailAddress}
    - periods_length_exception: 1 = exception day (Sunday/holiday), 2 = normal day

    Sunday 09:00 is special: there is no Sat 21:00 → Sun 09:00 overnight shift, but the
    report still covers DEI errors from that window. The recipient is the engineer on the
    exceptional Sun 09:00-12:00 shift (fetched from today's timeline starting at 09:00 BRT,
    not D-1 / midnight). Querying from midnight can return an earlier Primary period
    (e.g. 00:00 BRT) and miss the 09:00-12:00 override/short shift.
    """
    anchor = now_sp or datetime.now(tz=SP_TZ)
    today = anchor.strftime("%Y-%m-%d")
    sunday_morning = _is_sunday_morning_report(anchor)

    if sunday_morning:
        shift_date = today
        periods_length_exception = 1
        logger.info(
            "Sunday morning report — fetching exceptional shift on %s (09:00-12:00 BRT). "
            "DEI errors still cover Sat 21:00 → Sun 09:00 (no overnight on-call).",
            shift_date,
        )
        # Start the timeline at 09:00 BRT so finalTimeline is anchored on the exceptional
        # short shift. A midnight (T00:00:00Z) window can surface an earlier Primary
        # period (hour=0) and omit the 09:00-12:00 responder (prod 2026-08-16).
        timeline = _get_schedule_timeline(
            cloud_id, jira_ops_auth, shift_date, time_suffix="T12:00:00Z"
        )
        rotations = timeline.get("finalTimeline", {}).get("rotations", [])
        recipients = _recipients_from_rotations(
            rotations,
            jira_ops_auth,
            periods_length_exception=periods_length_exception,
            sunday_morning=True,
        )
        if not recipients:
            logger.warning(
                "No 09:00 BRT recipient in T12:00:00Z timeline — retrying Sunday fetch "
                "with T00:00:00Z fallback window."
            )
            timeline = _get_schedule_timeline(
                cloud_id, jira_ops_auth, shift_date, time_suffix="T00:00:00Z"
            )
            rotations = timeline.get("finalTimeline", {}).get("rotations", [])
            recipients = _recipients_from_rotations(
                rotations,
                jira_ops_auth,
                periods_length_exception=periods_length_exception,
                sunday_morning=True,
            )
        return recipients, periods_length_exception

    shift_date = (anchor - timedelta(days=1)).strftime("%Y-%m-%d")
    logger.info("today=%s, shift_date=%s", today, shift_date)

    timeline = _get_schedule_timeline(cloud_id, jira_ops_auth, shift_date)
    rotations = timeline.get("finalTimeline", {}).get("rotations", [])
    periods_length_exception = len(rotations[0].get("periods", [])) if rotations else 2
    logger.info("periods_length_exception=%s", periods_length_exception)

    if periods_length_exception == 1:
        logger.info(
            "Exception day detected on D-1 (%s) — re-fetching with midnight UTC window "
            "to capture the 09:00 BRT exception shift.",
            shift_date,
        )
        timeline = _get_schedule_timeline(
            cloud_id, jira_ops_auth, shift_date, time_suffix="T00:00:00Z"
        )
        rotations = timeline.get("finalTimeline", {}).get("rotations", [])

    recipients = _recipients_from_rotations(
        rotations,
        jira_ops_auth,
        periods_length_exception=periods_length_exception,
        sunday_morning=False,
    )
    return recipients, periods_length_exception


def _is_voice_sent_notification(log_text: str) -> bool:
    """Return True when a Jira Ops log entry records a sent voice notification."""
    if re.search(r"->\s*Sent\b", log_text) is None:
        return False
    channel_match = re.search(r"\[(email|sms|voice)\]", log_text, re.IGNORECASE)
    if channel_match:
        return channel_match.group(1).lower() == "voice"
    if "notification" not in log_text.lower():
        return False
    relaxed_match = re.search(r"\[?(email|sms|voice)\]?", log_text, re.IGNORECASE)
    return relaxed_match is not None and relaxed_match.group(1).lower() == "voice"


def _next_page_after(next_link: str | None) -> str | None:
    """Extract the ``after`` cursor from a Jira Ops paginated response link."""
    if not next_link:
        return None
    after_values = parse_qs(urlparse(next_link).query).get("after")
    return after_values[0] if after_values else None


def _fetch_alerts_in_window(
    cloud_id: str,
    jira_ops_auth: HTTPBasicAuth,
    jql_query: str,
    start_ts_ms: int,
    end_ts_ms: int,
) -> list[dict]:
    """List all alerts in the time window, following Jira Ops offset pagination.

    Returns dicts with ``id``, ``message``, ``tags``, ``alias`` and ``created_at``.
    ``start_ts_ms`` and ``end_ts_ms`` are Unix epoch milliseconds (Jira Ops API format).
    """
    alerts: list[dict] = []
    offset = 0
    page_size = 100
    alerts_url = f"{JIRA_OPS_API_BASE}/{cloud_id}/v1/alerts"
    headers = {"Accept": "application/json"}

    while True:
        resp = requests.get(
            alerts_url,
            params={
                "query": jql_query,
                "from": start_ts_ms,
                "to": end_ts_ms,
                "size": page_size,
                "offset": offset,
            },
            headers=headers,
            auth=jira_ops_auth,
        )
        if resp.status_code != 200:
            logger.warning(
                "Alerts API returned %s at offset %d — stopping pagination",
                resp.status_code,
                offset,
            )
            break

        batch = resp.json().get("values", [])
        for item in batch:
            alert_id = item.get("id")
            if not alert_id:
                continue
            alerts.append(
                {
                    "id": alert_id,
                    "message": item.get("message", "") or "",
                    "tags": _normalize_tags(item.get("tags")),
                    "alias": item.get("alias") or "",
                    "created_at": item.get("createdAt") or item.get("created_at"),
                }
            )

        if len(batch) < page_size:
            break
        offset += len(batch)

    return alerts


def _alert_had_voice_call(
    cloud_id: str,
    jira_ops_auth: HTTPBasicAuth,
    alert_id: str,
) -> bool:
    """Return True when the alert generated at least one sent voice notification."""
    after: str | None = None
    logs_url = f"{JIRA_OPS_API_BASE}/{cloud_id}/v1/alerts/{alert_id}/logs"
    headers = {"Accept": "application/json"}

    while True:
        params: dict[str, int | str] = {"size": 100}
        if after is not None:
            params["after"] = after

        log_resp = requests.get(
            logs_url,
            params=params,
            headers=headers,
            auth=jira_ops_auth,
        )
        if log_resp.status_code != 200:
            return False

        payload = log_resp.json() or {}
        for entry in payload.get("values", []):
            if _is_voice_sent_notification(entry.get("log", "")):
                return True

        links = payload.get("links") or {}
        after = _next_page_after(links.get("next"))
        if after is None:
            break

    return False


def _extract_dag_from_alert(
    message: str,
    known_dag_ids: set[str] | None,
    extra_texts: list[str] | None = None,
) -> str:
    """Best-effort resolution of the DAG behind a wakeup alert.

    Matches the alert message (plus optional alias/tags) against the set of known
    active DAG IDs (longest match wins, so a more specific 'domain.sub.dag' is
    preferred over 'domain.sub'). Falls back to the raw message when no known DAG
    ID is found, and to a placeholder when the message is empty.
    """
    parts = [(message or "").strip()]
    if extra_texts:
        parts.extend(text for text in extra_texts if text)
    text = " ".join(parts).strip()
    if known_dag_ids:
        matches = [dag_id for dag_id in known_dag_ids if dag_id and dag_id in text]
        if matches:
            return max(matches, key=len)
    return (message or "").strip() or text or "Alerta sem descrição"


def _alert_query_window(
    periods_length_exception: int,
    now_sp: datetime | None = None,
) -> tuple[datetime, datetime]:
    """Return the Jira Ops alert query window for the shift being reported."""
    now = now_sp or datetime.now(tz=SP_TZ)
    if _is_sunday_morning_report(now) and periods_length_exception == 1:
        start_dt = (now - timedelta(days=1)).replace(
            hour=21, minute=0, second=0, microsecond=0
        )
        end_dt = now.replace(hour=12, minute=0, second=0, microsecond=0)
    elif periods_length_exception != 1:
        start_dt = (now - timedelta(days=1)).replace(
            hour=21, minute=0, second=0, microsecond=0
        )
        end_dt = now.replace(hour=12, minute=0, second=0, microsecond=0)
    else:
        start_dt = now.replace(hour=9, minute=0, second=0, microsecond=0)
        end_dt = now.replace(hour=12, minute=0, second=0, microsecond=0)
    return start_dt, end_dt


def _fetch_classified_alerts(
    cloud_id: str,
    jira_ops_auth: HTTPBasicAuth,
    periods_length_exception: int,
    now_sp: datetime | None = None,
    known_dag_ids: set[str] | None = None,
) -> list[dict]:
    """Fetch shift-window alerts and classify origin + whether voice was sent.

    Returns one dict per alert with ``alert_id``, ``message``, ``tags``, ``alias``,
    ``created_at``, ``dag``, ``source_label`` and ``had_voice``.
    """
    start_dt, end_dt = _alert_query_window(periods_length_exception, now_sp=now_sp)
    start_ts_ms = int(start_dt.timestamp() * 1000)
    end_ts_ms = int(end_dt.timestamp() * 1000)
    jql_query = (
        f'responders: "Data Engineering"'
        f" AND createdAt > {start_ts_ms} AND createdAt < {end_ts_ms}"
    )

    logger.info(
        "Querying alerts: %s → %s",
        start_dt.strftime("%Y-%m-%dT%H:%M"),
        end_dt.strftime("%Y-%m-%dT%H:%M"),
    )

    alerts = _fetch_alerts_in_window(
        cloud_id, jira_ops_auth, jql_query, start_ts_ms, end_ts_ms
    )
    if not alerts:
        logger.info("No alerts found in window")
        return []

    logger.info("Found %d alerts in window", len(alerts))

    classified: list[dict] = []
    for alert in alerts:
        message = alert.get("message", "")
        tags = _normalize_tags(alert.get("tags"))
        alias = alert.get("alias") or ""
        had_voice = _alert_had_voice_call(cloud_id, jira_ops_auth, alert["id"])
        classified.append(
            {
                "alert_id": alert["id"],
                "message": message,
                "tags": tags,
                "alias": alias,
                "created_at": alert.get("created_at"),
                "dag": _extract_dag_from_alert(
                    message, known_dag_ids, extra_texts=[alias, *tags]
                ),
                "source_label": _classify_incident_source(message, tags, alias),
                "had_voice": had_voice,
            }
        )
    voice_count = sum(1 for alert in classified if alert["had_voice"])
    logger.info("%d alerts with voice calls", voice_count)
    return classified


def _count_voice_wakeups(
    cloud_id: str,
    jira_ops_auth: HTTPBasicAuth,
    periods_length_exception: int,
    now_sp: datetime | None = None,
    known_dag_ids: set[str] | None = None,
) -> list[dict]:
    """List distinct alerts that triggered a voice call (acordamentos) in the shift window.

    Returns one classified-alert dict per alert that generated at least one sent
    voice notification; ``len()`` of the result is the wakeup count.
    """
    classified = _fetch_classified_alerts(
        cloud_id,
        jira_ops_auth,
        periods_length_exception,
        now_sp=now_sp,
        known_dag_ids=known_dag_ids,
    )
    return [alert for alert in classified if alert.get("had_voice")]


def _dag_id_in_text(dag_id: str, text: str) -> bool:
    """Return True when ``dag_id`` appears as a whole DAG token in ``text``.

    Avoids matching ``bietlejuice.dw_listing`` inside ``bietlejuice.dw_listing_owners``.
    Hyphens are allowed as separators so Rubinho aliases
    (``dag-runtime-{dag_id}-{run_id}``) still match.
    """
    if not dag_id or not text:
        return False
    pattern = rf"(?<![A-Za-z0-9._]){re.escape(dag_id)}(?![A-Za-z0-9._])"
    return re.search(pattern, text) is not None


def _alert_matches_issue(alert: dict, dag_id: str) -> bool:
    """Return True when the alert is associated with the DEI issue DAG id."""
    if not dag_id:
        return False
    if alert.get("dag") == dag_id:
        return True
    haystack = " ".join(
        [alert.get("message") or "", alert.get("alias") or "", alert.get("dag") or ""]
        + list(alert.get("tags") or [])
    )
    return _dag_id_in_text(dag_id, haystack)


def _issue_created_sort_key(issue: dict) -> datetime:
    """Sort key so earlier DEI cards are paired before later ones."""
    parsed = _parse_optional_datetime(issue.get("created"))
    if parsed is None:
        return datetime.max.replace(tzinfo=SP_TZ)
    return parsed


def _enrich_issues_from_alerts(issues: list[dict], alerts: list[dict]) -> list[dict]:
    """Attach ``source_label`` and ``had_voice`` to each DEI issue from Jira Ops alerts.

    Matches on DAG id (issue summary) and, when several alerts share that DAG,
    picks the unused alert whose ``created_at`` is closest to the issue ``created``.
    Issues are paired in created order so Jira search order cannot steal the
    nearer alert for a later card. The returned list keeps the original order.
    """
    used_alert_ids: set[str] = set()
    for issue in sorted(issues, key=_issue_created_sort_key):
        dag_id = (issue.get("summary") or "").strip()
        issue_created = _parse_optional_datetime(issue.get("created"))
        candidates = [
            alert
            for alert in alerts
            if alert.get("alert_id") not in used_alert_ids
            and _alert_matches_issue(alert, dag_id)
        ]
        if not candidates:
            issue["source_label"] = SOURCE_UNKNOWN
            issue["had_voice"] = False
            continue

        def _delta(alert: dict, created: datetime | None = issue_created) -> timedelta:
            alert_created = _parse_optional_datetime(alert.get("created_at"))
            if alert_created is None or created is None:
                return timedelta.max
            return abs(alert_created - created)

        best = min(candidates, key=_delta)
        used_alert_ids.add(best["alert_id"])
        issue["source_label"] = best.get("source_label") or SOURCE_UNKNOWN
        issue["had_voice"] = bool(best.get("had_voice"))
    return issues


def _issue_error_entry(issue: dict) -> dict:
    """Build one ``error_list`` item for the notification payload."""
    return {
        "url": f"{DEI_BOARD_URL}?selectedIssue={issue['key']}",
        "key": issue["key"],
        "owner": issue.get("owner"),
        "source_label": issue.get("source_label") or SOURCE_UNKNOWN,
        "had_voice": bool(issue.get("had_voice")),
    }


def _format_issue_alert_text(issue: dict) -> str:
    """Render one DEI issue line for the Google Chat card."""
    owner = issue.get("owner") or "N/A"
    parts = [f'<a href="{issue["url"]}">{issue["key"]}</a>', owner]
    source_label = issue.get("source_label")
    if source_label:
        parts.append(source_label)
    if issue.get("had_voice"):
        parts.append("Acordamento")
    return " - ".join(parts)


def _is_gchat_webhook(url: str) -> bool:
    """Return True when the webhook URL points directly to Google Chat (not notification-hub)."""
    return "googleapis.com" in url


def _wrap_for_gchat(payload: dict) -> dict:
    """
    Convert the notification-hub payload into a GChat cardsV2 card that mirrors
    the production notification-hub rendering (header, dividers, Portuguese labels).

    Used only when the webhook URL is a direct Google Chat incoming webhook
    (e.g. for Forno testing) instead of the notification-hub endpoint.
    """
    oncall = payload.get("email", "?")
    if isinstance(oncall, list):
        oncall = str(oncall)
    start_time = payload.get("start_time", "?")
    called_count = payload.get("called_count", "0")
    wakeup_dags = payload.get("wakeup_dags", [])
    error_list = payload.get("error_list", [])

    summary_text = (
        f"<b>Plantonista:</b> {oncall}<br>"
        f"<b>Início:</b> {start_time}<br>"
        f"<b>Acordamentos:</b> {called_count}"
    )
    if wakeup_dags:
        summary_text += "".join(f"<br>• {dag_name}" for dag_name in wakeup_dags)

    if error_list:
        voice_count = sum(1 for issue in error_list if issue.get("had_voice"))
        header = f"Tivemos {len(error_list)} erros:"
        if voice_count:
            header = f"Tivemos {len(error_list)} erros ({voice_count} com chamada):"
        alerts_widgets: list[dict] = [{"textParagraph": {"text": header}}] + [
            {"textParagraph": {"text": _format_issue_alert_text(issue)}}
            for issue in error_list
        ]
    else:
        alerts_widgets = [{"textParagraph": {"text": "Nenhum erro no período."}}]

    return {
        "cardsV2": [
            {
                "cardId": "dag-rotation-forno",
                "card": {
                    "header": {"title": "Bot do Platão Data Engineers"},
                    "sections": [
                        {
                            "widgets": [
                                {"textParagraph": {"text": summary_text}},
                            ],
                        },
                        {
                            "header": "Alertas",
                            "widgets": alerts_widgets,
                        },
                    ],
                },
            }
        ]
    }


def _environment_suffix() -> str:
    """Return a display label for the current deployment environment."""
    raw = (os.environ.get("ENVIRONMENT") or "").strip().lower()
    if raw == "forno":
        return " · FORNO"
    if raw == "prod":
        return " · PROD"
    return ""


@provide_session
def notify_dag_rotation(session=None, **context):
    """
    Post on-call rotation notification.

    Steps:
    1. Fetch DEI Jira issues from the previous on-call window.
    2. Resolve missing incident owners using the Airflow DagModel (DAG summary = DAG ID).
    3. Write back inferred owners to the DEI Jira issues.
    4. Retrieve the current on-call engineer(s) from the Jira Ops schedule.
    5. Fetch Jira Ops alerts in the shift window, classify Airflow vs Rubinho
       (runtime anomaly), and mark which ones sent a voice wakeup.
    6. Attach source + acordamento flags to each DEI issue from the matching alert.
    7. POST summary payload to notification-hub (DAG_Rotation space).
    8. Optionally POST to iam-alerts space for Cyber Security issues (best-effort, non-fatal).

    DAG run conf (optional):
    - load_start_date: YYYY-MM-DD — simulate the 09:00 SP notification for a past date (backtests).
    """
    dag_run = context.get("dag_run")
    dag_run_conf = dag_run.conf if dag_run and dag_run.conf else {}
    load_start_date = dag_run_conf.get("load_start_date")
    now_sp = _resolve_now_sp(load_start_date)
    if load_start_date:
        logger.info(
            "Using load_start_date=%s (09:00 America/Sao_Paulo)", load_start_date
        )

    config = ConfigurationService()
    webhook_keys = config.get_config("notification_webhooks_keys")

    dag_rotation_variable_key = webhook_keys["dag_rotation"]
    webhook_url = Variable.get(dag_rotation_variable_key, default_var=None)

    jira_secret = json.loads(Variable.get("SECRET_JIRA_API"))
    jira_ops_secret = json.loads(Variable.get("SECRET_JIRA_OPS_API"))
    cloud_id = jira_ops_secret["cloud_id"]

    jira_auth = HTTPBasicAuth(jira_secret["username"], jira_secret["token"])
    jira_ops_auth = HTTPBasicAuth(jira_ops_secret["username"], jira_ops_secret["token"])

    dt_start = (now_sp - timedelta(days=1)).strftime("%Y-%m-%d")
    dt_end = now_sp.strftime("%Y-%m-%d")
    if _is_sunday_morning_report(now_sp):
        logger.info(
            "On-call window: %s 21:00 → %s 09:00 (America/Sao_Paulo, no overnight on-call; "
            "exceptional shift %s 09:00-12:00)",
            dt_start,
            dt_end,
            dt_end,
        )
    else:
        logger.info(
            "On-call window: %s 21:00 → %s 09:00 (America/Sao_Paulo)", dt_start, dt_end
        )
    logger.info(_environment_suffix() or "· local/other")

    dag_owner_map = {
        dm.dag_id: _clean_dag_owner(dm.owners or "")
        for dm in session.query(DagModel).filter(DagModel.is_active.is_(True)).all()
    }
    logger.info("Loaded %d active DAG owners from Airflow DB", len(dag_owner_map))

    issues = _fetch_dei_issues(jira_auth, dt_start, dt_end)
    logger.info("Found %d DEI issues in window", len(issues))

    issues = _resolve_issue_owners(issues, dag_owner_map, jira_auth)

    recipients, periods_length_exception = _get_oncall_recipients(
        cloud_id, jira_ops_auth, now_sp=now_sp
    )

    if not recipients:
        logger.warning("No on-call recipients found — skipping notification.")
        return

    classified_alerts = _fetch_classified_alerts(
        cloud_id,
        jira_ops_auth,
        periods_length_exception,
        now_sp=now_sp,
        known_dag_ids=set(dag_owner_map),
    )
    issues = _enrich_issues_from_alerts(issues, classified_alerts)
    wakeups = [alert for alert in classified_alerts if alert.get("had_voice")]
    wakeup_count = len(wakeups)
    # Unique DAG names woken during the shift, preserving first-seen order.
    wakeup_dags = list(dict.fromkeys(w["dag"] for w in wakeups))
    logger.info("Voice wakeups: %d (DAGs: %s)", wakeup_count, wakeup_dags)

    oncall_emails = list(dict.fromkeys(r["emailAddress"] for r in recipients))
    oncall_email = " + ".join(oncall_emails)

    shift_date = now_sp if periods_length_exception == 1 else now_sp - timedelta(days=1)
    shift_hour = 9 if periods_length_exception == 1 else 21
    start_time = shift_date.replace(
        hour=shift_hour, minute=0, second=0, microsecond=0
    ).strftime("%Y-%m-%dT%H:%M")

    payload = {
        "email": oncall_email,
        "start_time": start_time,
        "called_count": str(wakeup_count) if wakeup_count > 0 else "0",
        "wakeup_dags": wakeup_dags,
        "error_list": [_issue_error_entry(issue) for issue in issues],
    }

    if not webhook_url:
        logger.warning(
            "Airflow Variable '%s' is not set. Create it with the notification-hub URL for DAG_Rotation.",
            dag_rotation_variable_key,
        )
        logger.info("Payload would have been: %s", json.dumps(payload))
        return

    notification_headers = {"Content-type": "application/json"}
    outgoing_payload = (
        _wrap_for_gchat(payload) if _is_gchat_webhook(webhook_url) else payload
    )
    resp = requests.post(
        webhook_url, json=outgoing_payload, headers=notification_headers
    )
    resp.raise_for_status()
    logger.info(
        "DAG_Rotation notification sent — %d issues, %d wakeups",
        len(issues),
        wakeup_count,
    )

    iam_alerts_key = webhook_keys.get("iam_alerts")
    iam_alerts_url = (
        Variable.get(iam_alerts_key, default_var=None) if iam_alerts_key else None
    )
    cyber_sec_issues = [
        i for i in issues if i.get("owner") == "Tech Platform Cyber Security"
    ]
    if cyber_sec_issues and iam_alerts_url:
        iam_payload = {
            **payload,
            "error_list": [_issue_error_entry(issue) for issue in cyber_sec_issues],
        }
        iam_send_payload = (
            _wrap_for_gchat(iam_payload)
            if _is_gchat_webhook(iam_alerts_url)
            else iam_payload
        )
        try:
            iam_resp = requests.post(
                iam_alerts_url, json=iam_send_payload, headers=notification_headers
            )
            iam_resp.raise_for_status()
            logger.info(
                "iam-alerts notification sent — %d Cyber Security issue(s)",
                len(cyber_sec_issues),
            )
        except Exception as exc:
            logger.error("Failed to send iam-alerts notification (non-fatal): %s", exc)


with DAG(
    dag_id="governance.notify_dag_rotation",
    default_args={
        "owner": DAGOwnerEnum.DATA_PLATFORM,
        "start_date": datetime(2026, 6, 1, 0, 0, 0, tzinfo=LOCAL_TZ),
    },
    description=(
        "Daily post on-call rotation notification. Fetches DEI Jira incidents from "
        "the previous on-call window (D-1 21:00 → D 09:00 SP), infers missing "
        "incident owners from the Airflow DagModel, classifies Jira Ops alerts as "
        "Airflow failure vs Rubinho runtime anomaly, counts voice wakeups, "
        "and POSTs the summary to notification-hub (DAG_Rotation space). "
        "Migrated from the Databricks Post-OnCall notebook (DBP-1491)."
    ),
    schedule="0 9 * * *",
    catchup=False,
    tags=["monitoring", "platform", "oncall"],
) as dag:
    PythonOperator(
        task_id="notify_dag_rotation",
        python_callable=notify_dag_rotation,
    )
