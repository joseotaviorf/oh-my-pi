"""Daily digest of open DEI incident cards — snapshot to Delta, then notify Google Chat.

Query source: datalake_jira.issues (enrich layer). "Open" = current_status_category != 'Done'.
Chat body is a Line (incident_owner) leaderboard plus hygiene: unassigned,
description not filled (empty or still the Jira pre-filled template), and
on going vs backlog from the card workflow status (In Progress / On going vs
To Do / Backlog). Concluded (Done) is excluded from this open digest.
Notification: Notification Hub inmetro route, ?space=agents-data-alarms
(base URL from spark_jobs/{environment}_conf.yml).
"""

from __future__ import annotations

import json
import re
from argparse import ArgumentParser, Namespace
from collections import defaultdict
from datetime import datetime, timezone

import requests
import yaml
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "report_open_incidents"
TABLE_NAME = "open_incidents_snapshot"
DEI_PROJECT_ID = "11446"
PARTITION_COLS = ["year", "month", "day"]
NOTIFICATION_HUB_INMETRO_BASE_KEY = "notification_hub_inmetro_webhook_base"
GCHAT_SPACE = "agents-data-alarms"
NO_LINE_LABEL = "no owner"
INCIDENT_TEMPLATE_MARKER = "Incident format template"
ON_GOING_STATUS_NAMES = frozenset(
    {"on going", "ongoing", "em andamento", "in progress"}
)
ON_GOING_STATUS_CATEGORIES = frozenset({"in progress"})
_URL_RE = re.compile(r"https?://\S+", re.I)
_INSTRUCTIONAL_SNIPPETS = (
    "Here we describe what happened, bringing inputs like which DAG is broken, "
    "on which task, and available task Logs from Airflow/Databricks that are "
    "relevant to the incident",
    "Here we describe the incident root cause, or what we think could be the it "
    "when we can't really track it down. We bring inputs like \"Spark loaded "
    "column X as INT even though it's STRING\", or even logs that clarify the "
    "error, like lack of permissions to a given google sheet.",
    "Here we bring what was done to solve the problem, always keeping in mind "
    'that if it was an temporary solution, like "Increased cluster resources" '
    'or "Marked task as success" only to put out the fire, we need to make it '
    "clear on the card, so the responsible team can start working on the "
    "permanent solution.",
)
_TEMPLATE_CHROME = (
    "Incident format template",
    "Complete Fill Guide:",
    "To-Do List",
    "On-Call Analytics Engineer",
    "Problem:",
    "Cause:",
    "Solution:",
)

logging_logger = QuintoAndarLogger(JOB_NAME)

OPEN_INCIDENTS_QUERY = f"""
    SELECT
        id_issue,
        summary,
        assignee,
        incident_owner,
        ts_created,
        issue_description,
        current_status,
        current_status_category
    FROM datalake_jira.issues
    WHERE id_project = '{DEI_PROJECT_ID}'
      AND is_deleted = false
      AND (current_status_category IS NULL OR current_status_category != 'Done')
"""


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("dag_name")
    parser.add_argument("schema")
    parser.add_argument("logical_ts")
    return parser.parse_args()


def _parse_logical_ts(raw: str) -> datetime:
    text = raw.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed


def _age_days(ts_created, as_of: datetime) -> int:
    if ts_created is None:
        return -1
    return (as_of - ts_created).days


def _line_label(incident_owner) -> str:
    if incident_owner is None:
        return NO_LINE_LABEL
    text = str(incident_owner).strip()
    return text or NO_LINE_LABEL


def _is_unassigned(assignee) -> bool:
    if assignee is None:
        return True
    return not str(assignee).strip()


def _normalize_description_text(text: str) -> str:
    collapsed = (
        text.replace("\xa0", " ")
        .replace("\u2019", "'")
        .replace("\u2018", "'")
        .replace("\u201c", '"')
        .replace("\u201d", '"')
    )
    return re.sub(r"\s+", " ", collapsed).strip()


def _flatten_description(raw) -> str:
    if raw is None:
        return ""
    text = str(raw).strip()
    if not text:
        return ""
    if text.startswith("{") and '"type"' in text:
        try:
            node = json.loads(text)
        except (json.JSONDecodeError, TypeError, ValueError):
            return _normalize_description_text(text)
        parts = []

        def _walk(value) -> None:
            if isinstance(value, dict):
                piece = value.get("text")
                if isinstance(piece, str) and piece:
                    parts.append(piece)
                _walk(value.get("content"))
            elif isinstance(value, list):
                for item in value:
                    _walk(item)

        _walk(node)
        return _normalize_description_text(" ".join(parts))
    return _normalize_description_text(text)


def _strip_auto_and_template_chrome(text: str) -> str:
    text = _normalize_description_text(text)
    for marker in ("Databricks Details (auto)", "Databricks Details"):
        idx = text.find(marker)
        if idx >= 0:
            text = text[:idx]
            break
    text = _URL_RE.sub(" ", text)
    for snippet in _INSTRUCTIONAL_SNIPPETS:
        text = text.replace(snippet, " ")
    for chrome in _TEMPLATE_CHROME:
        text = re.sub(re.escape(chrome), " ", text, flags=re.I)
    return re.sub(r"[\W_]+", "", text, flags=re.UNICODE)


def _is_description_filled(issue_description) -> bool:
    """False when empty or still the Jira pre-filled Problem/Cause/Solution template."""
    flat = _flatten_description(issue_description)
    if not flat.strip():
        return False
    leftover = _strip_auto_and_template_chrome(flat)
    if INCIDENT_TEMPLATE_MARKER.lower() in flat.lower():
        return bool(leftover)
    return True


def _is_on_going(current_status, current_status_category=None) -> bool:
    """Card workflow is being worked (not backlog, not concluded)."""
    name = str(current_status or "").strip().lower()
    category = str(current_status_category or "").strip().lower()
    return name in ON_GOING_STATUS_NAMES or category in ON_GOING_STATUS_CATEGORIES


def _format_message(rows, as_of: datetime) -> str:
    if not rows:
        return f"No open DEI incidents as of {as_of.date().isoformat()}."

    ages_by_line = defaultdict(list)
    unassigned_by_line = defaultdict(int)
    unfilled_by_line = defaultdict(int)
    on_going_by_line = defaultdict(int)
    for row in rows:
        line_name = _line_label(row.get("incident_owner"))
        ages_by_line[line_name].append(_age_days(row.get("ts_created"), as_of))
        if _is_unassigned(row.get("assignee")):
            unassigned_by_line[line_name] += 1
        if not _is_description_filled(row.get("issue_description")):
            unfilled_by_line[line_name] += 1
        if _is_on_going(row.get("current_status"), row.get("current_status_category")):
            on_going_by_line[line_name] += 1

    ranked = sorted(
        ages_by_line.items(), key=lambda item: (-len(item[1]), item[0].lower())
    )
    lines = [
        f"Open DEI incidents as of {as_of.date().isoformat()} — {len(rows)} total:"
    ]
    for line_name, ages in ranked:
        known_ages = [age for age in ages if age >= 0]
        if known_ages:
            age_part = f" (newest: {min(known_ages)}d, oldest: {max(known_ages)}d)"
        else:
            age_part = " (newest: unknown, oldest: unknown)"
        hygiene = (
            f" | on going {on_going_by_line[line_name]}"
            f" | unassigned {unassigned_by_line[line_name]}"
            f" | description not filled {unfilled_by_line[line_name]}"
        )
        lines.append(
            f"{line_name}: {len(ages)} opened DEI incidents{age_part}{hygiene}"
        )
    return "\n".join(lines)


def _notification_hub_inmetro_base(dag_name: str, environment: str) -> str | None:
    """Resolve Hub base URL from co-located spark_jobs/{environment}_conf.yml, then wheel config."""
    conf_file = f"{environment}_conf.yml"
    try:
        raw = DAGPackagesPathService.get_config_file_content_in_spark_jobs(
            dag_name, conf_file
        )
        value = (yaml.safe_load(raw) or {}).get(NOTIFICATION_HUB_INMETRO_BASE_KEY)
        if value:
            return str(value).strip()
    except FileNotFoundError:
        logging_logger.warning(
            f"m={JOB_NAME}, dag_name={dag_name}, conf_file={conf_file}, "
            "msg=Spark jobs env conf not found; falling back to ConfigurationService"
        )
    except Exception as error:  # noqa: BLE001
        logging_logger.warning(
            f"m={JOB_NAME}, dag_name={dag_name}, conf_file={conf_file}, error={error}"
        )

    try:
        return ConfigurationService(dag_name).get_config(
            NOTIFICATION_HUB_INMETRO_BASE_KEY
        )
    except (IndexError, KeyError, AttributeError):
        return None


def _notify(dag_name: str, environment: str, message: str, row_count: int) -> None:
    base_url = _notification_hub_inmetro_base(dag_name, environment)
    if not base_url:
        logging_logger.warning(
            f"m={JOB_NAME}, msg=Missing config key {NOTIFICATION_HUB_INMETRO_BASE_KEY!r}; "
            "skipping GChat notification"
        )
        return

    separator = "&" if "?" in base_url else "?"
    webhook_url = f"{base_url.rstrip('/')}{separator}space={GCHAT_SPACE}"
    payload = {
        "suite_name": "jira_open_incidents_report",
        "status": "ERROR" if row_count > 0 else "OK",
        "message": message,
    }
    try:
        response = requests.post(webhook_url, json=payload, timeout=30)
        response.raise_for_status()
        logging_logger.info(f"m={JOB_NAME}, msg=Notification Hub message sent")
    except Exception as error:  # noqa: BLE001 — a failed notify must not fail the snapshot write
        logging_logger.warning(f"m={JOB_NAME}, url={webhook_url}, error={error}")


def main() -> None:
    args = parse_arguments()
    logical_ts = _parse_logical_ts(args.logical_ts)

    spark_client = SparkClient(app_name=JOB_NAME)
    spark = spark_client.conn

    open_df = (
        spark.sql(OPEN_INCIDENTS_QUERY)
        .withColumn("year", F.lit(logical_ts.year))
        .withColumn("month", F.lit(logical_ts.month))
        .withColumn("day", F.lit(logical_ts.day))
    )

    rows = [row.asDict() for row in open_df.collect()]
    message = _format_message(rows, logical_ts)
    logging_logger.info(f"m={JOB_NAME}, open_incidents={len(rows)}")

    write_db = f"datalake_{args.schema}"
    table = f"{write_db}.{TABLE_NAME}"
    path = f"s3://{args.datalake_bucket}/enrich/{args.schema}/{TABLE_NAME}"
    metastore = MetastoreServiceFactory.create_loader_metastore_service(spark_client)
    metastore.create_database(write_db)
    DeltaLoader(spark_client.conn).load_table(
        table_name=table,
        path=path,
        source_df=open_df,
        partition_by=PARTITION_COLS,
    )
    metastore.refresh_table(write_db, TABLE_NAME)
    logging_logger.info(f"m={JOB_NAME}, table={table}")

    _notify(args.dag_name, args.environment, message, len(rows))


if __name__ == "__main__":
    main()
