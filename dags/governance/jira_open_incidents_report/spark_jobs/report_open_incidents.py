"""Daily digest of open DEI incident cards — snapshot to Delta, then notify Google Chat.

Query source: datalake_jira.issues (enrich layer). "Open" = current_status_category != 'Done'.
Chat card has two blocks: (1) a summary (date, total open, unassigned, not filled)
and (2) a per-domain (incident_owner) breakdown with only newest/oldest age, each
domain hyperlinked to its pre-filtered DEI board (all "Tech Platform" domains are
merged into one unlinked line). Concluded (Done) is excluded from this open digest.
Notification: Notification Hub generic route (cardsV2 so Chat renders line
breaks; inmetro nl2br becomes literal ``<br>`` in GChat text).
Space DAG_Rotation (base URL from spark_jobs/{environment}_conf.yml).
"""

from __future__ import annotations

import json
import re
from argparse import ArgumentParser, Namespace
from collections import defaultdict
from datetime import datetime, timezone
from urllib.parse import quote

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
INMETRO_WEBHOOK_PATH = "/webhook/inmetro"
GENERIC_WEBHOOK_PATH = "/webhook/generic"
GCHAT_SPACE = "DAG_Rotation"
NO_LINE_LABEL = "no owner"
INCIDENT_TEMPLATE_MARKER = "Incident format template"
TECH_PLATFORM_LABEL = "Tech Platform"
BOARD_URL_BASE = "https://quintoandar.atlassian.net/issues?filter=31118&jql="
BOARD_JQL_TEMPLATE = (
    'project = DEI AND status IN ("In Progress", "To Do") and '
    '"Incident Owner [Data Engineer][Dropdown]" = "{domain}"\n'
    "ORDER BY status ASC, created DESC"
)
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


def _board_url(domain: str) -> str:
    jql = BOARD_JQL_TEMPLATE.format(domain=domain)
    return BOARD_URL_BASE + quote(jql, safe="()")


def _domain_breakdown(rows, as_of: datetime) -> list[dict]:
    """One row per incident_owner, merging every "Tech Platform" domain into one (unlinked)."""
    ages_by_domain = defaultdict(list)
    for row in rows:
        domain = _line_label(row.get("incident_owner"))
        is_tech_platform = TECH_PLATFORM_LABEL.lower() in domain.lower()
        merged_key = TECH_PLATFORM_LABEL if is_tech_platform else domain
        ages_by_domain[merged_key].append(_age_days(row.get("ts_created"), as_of))

    breakdown = []
    for domain, ages in sorted(
        ages_by_domain.items(), key=lambda item: (-len(item[1]), item[0].lower())
    ):
        known_ages = [age for age in ages if age >= 0]
        breakdown.append(
            {
                "domain": domain,
                "count": len(ages),
                "newest": min(known_ages) if known_ages else None,
                "oldest": max(known_ages) if known_ages else None,
                "linked": domain not in (TECH_PLATFORM_LABEL, NO_LINE_LABEL),
            }
        )
    return breakdown


def _age_text(entry: dict, separator: str) -> str:
    if entry["newest"] is None:
        return f"newest: unknown{separator}oldest: unknown"
    return f"newest: {entry['newest']}d{separator}oldest: {entry['oldest']}d"


def _format_message(rows, as_of: datetime) -> str:
    """Plain-text digest for logs; the GChat card is built separately in `_build_card`."""
    if not rows:
        return f"No open DEI incidents as of {as_of.date().isoformat()}."

    total_unassigned = sum(1 for row in rows if _is_unassigned(row.get("assignee")))
    total_unfilled = sum(
        1 for row in rows if not _is_description_filled(row.get("issue_description"))
    )
    lines = [
        f"Open DEI incidents as of {as_of.date().isoformat()} — {len(rows)} total, "
        f"{total_unassigned} unassigned, {total_unfilled} not filled:"
    ]
    for entry in _domain_breakdown(rows, as_of):
        lines.append(
            f"• {entry['domain']}: {entry['count']} opened ({_age_text(entry, ', ')})"
        )
    return "\n".join(lines)


def _build_card(rows, as_of: datetime) -> dict:
    """Two-block GChat card: summary section, then per-domain section (linked to its board)."""
    if not rows:
        text = f"No open DEI incidents as of {as_of.date().isoformat()}."
        return {
            "cardsV2": [
                {
                    "cardId": JOB_NAME,
                    "card": {
                        "header": {"title": "Open DEI incidents"},
                        "sections": [{"widgets": [{"textParagraph": {"text": text}}]}],
                    },
                }
            ]
        }

    total_unassigned = sum(1 for row in rows if _is_unassigned(row.get("assignee")))
    total_unfilled = sum(
        1 for row in rows if not _is_description_filled(row.get("issue_description"))
    )
    summary_text = (
        f"Date: {as_of.date().isoformat()}<br>"
        f"Total open: {len(rows)}<br>"
        f"Unassigned: {total_unassigned}<br>"
        f"Not filled: {total_unfilled}"
    )

    # decoratedText + button (openLink) instead of a raw <a href> in textParagraph:
    # this exact widget shape already round-trips through Google Chat incoming
    # webhooks elsewhere in this repo (notify_stale_dags.py, notify_broken_dags.py),
    # whereas an HTML anchor inside textParagraph text has no verified precedent here.
    domain_widgets = []
    for entry in _domain_breakdown(rows, as_of):
        widget = {
            "decoratedText": {
                "text": f"<b>{entry['domain']}</b>: {entry['count']} opened",
                "bottomLabel": _age_text(entry, " · "),
            }
        }
        if entry["linked"]:
            widget["decoratedText"]["button"] = {
                "text": "Open board",
                "onClick": {"openLink": {"url": _board_url(entry["domain"])}},
            }
        domain_widgets.append(widget)

    return {
        "cardsV2": [
            {
                "cardId": JOB_NAME,
                "card": {
                    "header": {"title": "Open DEI incidents"},
                    "sections": [
                        {
                            "header": "Summary",
                            "widgets": [{"textParagraph": {"text": summary_text}}],
                        },
                        {"header": "By domain", "widgets": domain_widgets},
                    ],
                },
            }
        ]
    }


def _generic_webhook_base(base_url: str) -> str:
    return base_url.replace(INMETRO_WEBHOOK_PATH, GENERIC_WEBHOOK_PATH)


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


def _notify(dag_name: str, environment: str, rows, as_of: datetime) -> None:
    base_url = _notification_hub_inmetro_base(dag_name, environment)
    if not base_url:
        logging_logger.warning(
            f"m={JOB_NAME}, msg=Missing config key {NOTIFICATION_HUB_INMETRO_BASE_KEY!r}; "
            "skipping GChat notification"
        )
        return

    generic_base = _generic_webhook_base(base_url)
    separator = "&" if "?" in generic_base else "?"
    webhook_url = f"{generic_base.rstrip('/')}{separator}space={GCHAT_SPACE}"
    payload = {"space": GCHAT_SPACE, **_build_card(rows, as_of)}
    logging_logger.info(
        f"m={JOB_NAME}, msg=Posting GChat card, open_incidents={len(rows)}"
    )
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
    logging_logger.info(f"m={JOB_NAME}, open_incidents={len(rows)}, digest={message}")

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

    _notify(args.dag_name, args.environment, rows, logical_ts)


if __name__ == "__main__":
    main()
