"""
    airflow parsing enforcement

    Note: this line above forces Airflow to parse this file for implemented DAGs
"""

import os
from datetime import datetime

import pendulum
import requests
from airflow import DAG
from airflow.configuration import conf
from airflow.datasets import Dataset
from airflow.models import DagModel, Variable
from airflow.operators.python import PythonOperator
from airflow.utils.db import provide_session
from sqlalchemy import text

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.configuration_service import ConfigurationService

AIRFLOW_URL = conf.get("webserver", "base_url")
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
STALE_THRESHOLD_MONTHS = 1

# Auto-pause is ON by default. Set Airflow Variable "notify_stale_dags_auto_pause_disabled" to "true" to opt out.
_AUTO_PAUSE_DISABLED_VARIABLE_KEY = "notify_stale_dags_auto_pause_disabled"

_STALE_QUERY = text("""
    WITH last_success AS (
        SELECT dag_id, MAX(start_date) AS ts_last_success
        FROM dag_run
        WHERE state = 'success'
        GROUP BY dag_id
    )
    SELECT
        d.dag_id,
        d.owners,
        d.schedule_interval,
        d.fileloc,
        ls.ts_last_success
    FROM dag d
    LEFT JOIN last_success ls ON d.dag_id = ls.dag_id
    WHERE d.is_active = TRUE
      AND d.is_paused = FALSE
      AND (
          ls.ts_last_success IS NULL
          OR ls.ts_last_success < NOW() - INTERVAL ':threshold months'
      )
    ORDER BY ls.ts_last_success ASC NULLS FIRST
""".replace(":threshold months", f"{STALE_THRESHOLD_MONTHS} months"))

_EXCLUDED_SCHEDULE_INTERVALS = {"Dataset", None}
_EXCLUDED_DAG_ID_PREFIXES = ("quintoml.",)


def _should_notify(row) -> bool:
    """Skip event-driven and manually-triggered DAGs — they are not stale by definition."""
    schedule = row.schedule_interval
    dag_id = row.dag_id
    if schedule in _EXCLUDED_SCHEDULE_INTERVALS or schedule == "null":
        return False
    if any(dag_id.startswith(prefix) for prefix in _EXCLUDED_DAG_ID_PREFIXES):
        return False
    return True


def _environment_suffix_for_card() -> str:
    """Append deployment label for GChat when Airflow is FORNO or PROD."""
    raw = (os.environ.get("ENVIRONMENT") or "").strip().lower()
    if raw == "forno":
        return " · FORNO"
    if raw == "prod":
        return " · PROD"
    return ""


def _build_card(stale_rows) -> dict:
    widgets = []
    for row in stale_rows:
        last_run = row.ts_last_success.strftime("%Y-%m-%d") if row.ts_last_success else "never"
        dag_url = f"{AIRFLOW_URL}/dags/{row.dag_id}/graph"
        widgets.append({
            "decoratedText": {
                "text": f"<b>{row.dag_id}</b>",
                "bottomLabel": f"owner: {row.owners} | schedule: {row.schedule_interval} | last success: {last_run}",
                "button": {
                    "text": "Open in Airflow",
                    "onClick": {"openLink": {"url": dag_url}},
                },
            }
        })

    return {
        "cardsV2": [
            {
                "cardId": "stale_dags_report",
                "card": {
                    "header": {
                        "title": f"🕸️ Stale DAG Report — {datetime.now().strftime('%Y-%m-%d')}",
                        "subtitle": (
                            f"Active DAGs with no successful run for at least "
                            f"{STALE_THRESHOLD_MONTHS} month"
                            f"{'s' if STALE_THRESHOLD_MONTHS != 1 else ''}"
                            f"{_environment_suffix_for_card()}"
                        ),
                        "imageUrl": "https://airflow.apache.org/docs/apache-airflow/stable/_images/pin_large.png",
                        "imageType": "CIRCLE",
                    },
                    "sections": [
                        {
                            "header": f"🚨 {len(stale_rows)} stale DAG(s) detected",
                            "widgets": widgets,
                        },
                    ],
                },
            }
        ]
    }


def _pause_dag(dag_id: str, session) -> None:
    """Pause a DAG in-place using the ORM — no REST auth required."""
    dag_model = session.query(DagModel).filter(DagModel.dag_id == dag_id).first()
    if dag_model is None:
        print(f"  ⚠️  DagModel not found for {dag_id} — skipping pause.")
        return
    dag_model.is_paused = True
    session.flush()
    print(f"  ⏸️  Paused {dag_id}")


@provide_session
def notify_stale_dags(session=None, **_):
    # Resolve webhook Airflow Variable key from notification_webhooks_keys["stale_dag"] (same key name in all envs).
    config = ConfigurationService()
    webhook_variable_key = config.get_config("notification_webhooks_keys")["stale_dag"]
    webhook_url = Variable.get(webhook_variable_key, default_var=None)
    auto_pause = Variable.get(_AUTO_PAUSE_DISABLED_VARIABLE_KEY, default_var="false").strip().lower() != "true"
    print(
        "notify_stale_dags diagnostics: "
        f"ENVIRONMENT={os.environ.get('ENVIRONMENT', '(unset)')}, "
        f"webhook_variable_key={webhook_variable_key}, "
        f"webhook_configured={'yes' if webhook_url else 'no'}, "
        f"auto_pause={auto_pause}"
    )

    rows = session.execute(_STALE_QUERY).fetchall()

    notifiable = [r for r in rows if _should_notify(r)]

    if not notifiable:
        print(
            "✅ No stale scheduled DAGs found — nothing to report. "
            "GChat is only sent when at least one active DAG matches the staleness rules "
            f"(cron-like schedule, not Dataset/manual; last success older than "
            f"{STALE_THRESHOLD_MONTHS} month{'s' if STALE_THRESHOLD_MONTHS != 1 else ''}). "
            "The webhook Variable is not used in this case."
        )
        return

    print(f"🕸️ {len(notifiable)} stale DAG(s) to report:")
    for row in notifiable:
        last_run = row.ts_last_success.strftime("%Y-%m-%d") if row.ts_last_success else "never"
        print(f"  • {row.dag_id} | owner: {row.owners} | last success: {last_run}")

    if auto_pause:
        print(f"⏸️  Auto-pause is ENABLED — pausing {len(notifiable)} DAG(s)...")
        for row in notifiable:
            _pause_dag(row.dag_id, session)
        session.commit()
        print("✅ All stale DAGs paused.")
    else:
        print(
            f"ℹ️  Auto-pause is DISABLED via Variable '{_AUTO_PAUSE_DISABLED_VARIABLE_KEY}'. "
            "Remove the Variable or set it to 'false' to re-enable auto-pausing."
        )

    if not webhook_url:
        print(
            f"⚠️  Airflow Variable '{webhook_variable_key}' is not set. "
            "In Admin → Variables, create that key with the Google Chat incoming webhook URL "
            "(key name comes from notification_webhooks_keys.stale_dag in packaged env YAML)."
        )
        return

    payload = _build_card(notifiable)
    response = requests.post(webhook_url, json=payload)
    try:
        response.raise_for_status()
        print("✅ GChat notification sent successfully.")
    except Exception as e:
        print(f"❌ Failed to send GChat notification: {e}")
        raise


with DAG(
    dag_id="airflow.notify_stale_dags",
    default_args={
        "owner": DAGOwnerEnum.DATA_LIFE_CYCLE,
        "start_date": datetime(2026, 4, 28, 0, 0, 0, tzinfo=LOCAL_TZ),
    },
    description=(
        "Triggered after enrich_stale_dags completes. Queries the Airflow DB for active DAGs "
        "with no successful run for at least 1 month and sends a GChat summary to the stale-DAG space "
        "(Airflow Variable from notification_webhooks_keys.stale_dag in env YAML; DPLT-860)."
    ),
    schedule=[
        Dataset("bietlejuice.enrich_stale_dags:load-enrich-stale-dags:first-run-of-day"),
    ],
    catchup=False,
    tags=["monitoring", "platform", "stale-dags"],
) as dag:

    PythonOperator(
        task_id="notify_stale_dags",
        python_callable=notify_stale_dags,
    )
