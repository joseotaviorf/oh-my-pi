"""Weekly digest of open DEI incident cards — snapshot to Delta, then notify Google Chat.

Query source: datalake_jira.issues (enrich layer). "Open" = current_status_category != 'Done'.
Chat body is a Line (incident_owner) leaderboard. Notification: Notification Hub inmetro
route, ?space=agents-data-alarms (base URL from spark_jobs/{environment}_conf.yml).
"""

from __future__ import annotations

import os
from argparse import ArgumentParser, Namespace
from collections import defaultdict
from datetime import datetime, timezone

import requests
import yaml
from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "report_open_incidents"
TABLE_NAME = "open_incidents_snapshot"
DEI_PROJECT_ID = "11446"
PARTITION_COLS = ["year", "month", "day"]
NOTIFICATION_HUB_INMETRO_BASE_KEY = "notification_hub_inmetro_webhook_base"
GCHAT_SPACE = "agents-data-alarms"
NO_LINE_LABEL = "no owner"

logging_logger = QuintoAndarLogger(JOB_NAME)

OPEN_INCIDENTS_QUERY = f"""
    SELECT id_issue, summary, assignee, incident_owner, ts_created
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


def _format_message(rows, as_of: datetime) -> str:
    if not rows:
        return f"No open DEI incidents as of {as_of.date().isoformat()}."

    ages_by_line = defaultdict(list)
    for row in rows:
        ages_by_line[_line_label(row.get("incident_owner"))].append(
            _age_days(row.get("ts_created"), as_of)
        )

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
        lines.append(f"{line_name}: {len(ages)} opened DEI incidents{age_part}")
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

    under_pytest = bool(os.environ.get("PYTEST_CURRENT_TEST"))
    if under_pytest:
        spark = SparkSession.getActiveSession() or SparkSession.builder.getOrCreate()
        spark_client = type("_TestSparkClient", (), {"conn": spark})()
    else:
        from bietlejuice.clients.db_clients import SparkClient

        spark_client = SparkClient(app_name=JOB_NAME)
        spark = spark_client.conn

    from pyspark.sql import functions as F

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
    if not under_pytest:
        from bietlejuice.services.metastore_services import MetastoreServiceFactory

        MetastoreServiceFactory.create_loader_metastore_service(
            spark_client
        ).create_database(write_db)
    DeltaLoader(spark_client.conn).load_table(
        table_name=table,
        path=path,
        source_df=open_df,
        partition_by=PARTITION_COLS,
    )
    if not under_pytest:
        MetastoreServiceFactory.create_loader_metastore_service(
            spark_client
        ).refresh_table(write_db, TABLE_NAME)
    logging_logger.info(f"m={JOB_NAME}, table={table}")

    _notify(args.dag_name, args.environment, message, len(rows))


if __name__ == "__main__":
    main()
