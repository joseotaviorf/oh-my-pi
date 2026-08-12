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
from airflow.models import Variable
from airflow.operators.python import PythonOperator
from airflow.utils.db import provide_session
from sqlalchemy import text

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.configuration_service import ConfigurationService

AIRFLOW_URL = conf.get("webserver", "base_url")
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
_LAST_SIGNATURE_VARIABLE_KEY = "notify_broken_dags_last_signature"
# Google Chat cardsV2 silently drops a section once it exceeds 100 widgets.
# Cap detail rows and keep one slot for an overflow summary when truncated.
_MAX_CARD_WIDGETS = 100

_QUARANTINED_QUERY = text(
    """
    SELECT d.dag_id, d.fileloc
    FROM dag d
    JOIN dag_tag t ON t.dag_id = d.dag_id
    WHERE t.name = 'broken-dag'
      AND d.is_active = TRUE
    ORDER BY d.dag_id
"""
)

_IMPORT_ERROR_QUERY = text(
    """
    SELECT filename, timestamp
    FROM import_error
    ORDER BY filename
"""
)


def _environment_suffix_for_card() -> str:
    """Append deployment label for GChat when Airflow is FORNO or PROD."""
    raw = (os.environ.get("ENVIRONMENT") or "").strip().lower()
    if raw == "forno":
        return " · FORNO"
    if raw == "prod":
        return " · PROD"
    return ""


def _build_card(quarantined_rows, import_error_rows) -> dict:
    total = len(quarantined_rows) + len(import_error_rows)
    detail_budget = _MAX_CARD_WIDGETS
    # Reserve one widget for an overflow summary when we cannot list everything.
    if total > _MAX_CARD_WIDGETS:
        detail_budget = _MAX_CARD_WIDGETS - 1

    widgets = []
    for row in quarantined_rows:
        if len(widgets) >= detail_budget:
            break
        dag_url = f"{AIRFLOW_URL}/dags/{row.dag_id}/graph"
        widgets.append(
            {
                "decoratedText": {
                    "text": f"<b>{row.dag_id}</b>",
                    "bottomLabel": f"quarantined (broken-dag) | file: {row.fileloc}",
                    "button": {
                        "text": "Open in Airflow",
                        "onClick": {"openLink": {"url": dag_url}},
                    },
                }
            }
        )
    for row in import_error_rows:
        if len(widgets) >= detail_budget:
            break
        widgets.append(
            {
                "decoratedText": {
                    "text": f"<b>{row.filename}</b>",
                    "bottomLabel": (
                        f"import error | since: "
                        f"{row.timestamp.strftime('%Y-%m-%d %H:%M') if row.timestamp else 'unknown'}"
                    ),
                }
            }
        )

    omitted = total - len(widgets)
    if omitted > 0:
        widgets.append(
            {
                "decoratedText": {
                    "text": f"<b>…and {omitted} more</b>",
                    "bottomLabel": (
                        "Card truncated to Google Chat's 100-widget limit; "
                        "see Airflow UI for the full broken-dag / import_error set."
                    ),
                }
            }
        )

    return {
        "cardsV2": [
            {
                "cardId": "broken_dags_report",
                "card": {
                    "header": {
                        "title": (
                            f"Broken DAG Report — {datetime.now().strftime('%Y-%m-%d')}"
                        ),
                        "subtitle": (
                            "Quarantined bundle builds (tag 'broken-dag') plus "
                            f"Airflow import errors{_environment_suffix_for_card()}"
                        ),
                        "imageUrl": (
                            "https://airflow.apache.org/docs/apache-airflow/"
                            "stable/_images/pin_large.png"
                        ),
                        "imageType": "CIRCLE",
                    },
                    "sections": [
                        {
                            "header": f"{total} broken DAG signal(s) detected",
                            "widgets": widgets,
                        },
                    ],
                },
            }
        ]
    }


@provide_session
def notify_broken_dags(session=None, **_):
    # Resolve webhook Airflow Variable key from notification_webhooks_keys["broken_dag"]
    # (same key name in all envs).
    config = ConfigurationService()
    webhook_variable_key = config.get_config("notification_webhooks_keys")["broken_dag"]
    webhook_url = Variable.get(webhook_variable_key, default_var=None)
    print(
        "notify_broken_dags diagnostics: "
        f"ENVIRONMENT={os.environ.get('ENVIRONMENT', '(unset)')}, "
        f"webhook_variable_key={webhook_variable_key}, "
        f"webhook_configured={'yes' if webhook_url else 'no'}"
    )

    quarantined_rows = session.execute(_QUARANTINED_QUERY).fetchall()
    import_error_rows = session.execute(_IMPORT_ERROR_QUERY).fetchall()

    quarantined_ids = [row.dag_id for row in quarantined_rows]
    import_error_filenames = [row.filename for row in import_error_rows]
    signature = ",".join(sorted(quarantined_ids + import_error_filenames))

    if not signature:
        Variable.set(_LAST_SIGNATURE_VARIABLE_KEY, "")
        print("✅ No broken DAGs — nothing to report.")
        return

    previous = Variable.get(_LAST_SIGNATURE_VARIABLE_KEY, default_var="")
    if signature == previous:
        print(
            f"ℹ️  Broken-DAG signature unchanged ({signature}); "
            "skipping GChat notification."
        )
        return

    print(
        f"🚨 {len(quarantined_rows)} quarantined DAG(s) and "
        f"{len(import_error_rows)} import error(s) to report:"
    )
    for dag_id in quarantined_ids:
        print(f"  • quarantined: {dag_id}")
    for filename in import_error_filenames:
        print(f"  • import_error: {filename}")

    if not webhook_url:
        print(
            f"⚠️  Airflow Variable '{webhook_variable_key}' is not set. "
            "In Admin → Variables, create that key with the Google Chat incoming webhook URL "
            "(key name comes from notification_webhooks_keys.broken_dag in packaged env YAML)."
        )
        return

    payload = _build_card(quarantined_rows, import_error_rows)
    response = requests.post(webhook_url, json=payload)
    try:
        response.raise_for_status()
        print("✅ GChat notification sent successfully.")
    except Exception as e:
        print(f"❌ Failed to send GChat notification: {e}")
        raise

    Variable.set(_LAST_SIGNATURE_VARIABLE_KEY, signature)


with DAG(
    dag_id="airflow.notify_broken_dags",
    default_args={
        "owner": DAGOwnerEnum.DATA_PLATFORM,
        "start_date": datetime(2026, 8, 5, tzinfo=LOCAL_TZ),
    },
    description=(
        "Every 30 minutes, reports DAGs quarantined by a bundle build failure "
        "(tag 'broken-dag') plus Airflow parse import errors, to the broken-DAG "
        "GChat space (Airflow Variable from notification_webhooks_keys.broken_dag "
        "in env YAML)."
    ),
    schedule="*/30 * * * *",
    catchup=False,
    tags=["monitoring", "platform", "broken-dags"],
) as dag:
    PythonOperator(
        task_id="notify_broken_dags",
        python_callable=notify_broken_dags,
    )
