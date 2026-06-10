"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs
"""

import os
from datetime import datetime

import pendulum
import requests
from airflow import DAG
from airflow.models import Variable
from airflow.operators.python import PythonOperator

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")

GCHAT_AIRBYTE_KEY_ROTATION_WEBHOOK = "GCHAT_AIRBYTE_KEY_ROTATION_WEBHOOK"

# TODO: replace with the official Airbyte key rotation runbook URL before merging.
AIRBYTE_KEY_ROTATION_RUNBOOK_URL = "https://docs.google.com/document/d/1c1WaJ_egrHz8sxBzhPA2uEqhZe4OvOADy_9x2A2gAyo/edit?tab=t.0#heading=h.4kme5kfknp0e"


def _environment_suffix_for_card() -> str:
    """Append deployment label for GChat when Airflow is FORNO or PROD."""
    raw = (os.environ.get("ENVIRONMENT") or "").strip().lower()
    if raw == "forno":
        return " · FORNO"
    if raw == "prod":
        return " · PROD"
    return ""


def _build_reminder_card() -> dict:
    today = datetime.now().strftime("%Y-%m-%d")
    return {
        "cardsV2": [
            {
                "cardId": "airbyte_key_rotation_reminder",
                "card": {
                    "header": {
                        "title": f"Airbyte Key Rotation Reminder — {today}",
                        "subtitle": (
                            "Please rotate the Airbyte API key before month-end"
                            f"{_environment_suffix_for_card()}"
                        ),
                        "imageUrl": "https://airflow.apache.org/docs/apache-airflow/stable/_images/pin_large.png",
                        "imageType": "CIRCLE",
                    },
                    "sections": [
                        {
                            "widgets": [
                                {
                                    "textParagraph": {
                                        "text": (
                                            "The Airbyte API key should be rotated monthly. "
                                            "Follow the runbook to generate a new key, update "
                                            "the secret stores, and revoke the previous key."
                                        )
                                    }
                                },
                                {
                                    "buttonList": {
                                        "buttons": [
                                            {
                                                "text": "Runbook: Rotate Airbyte Key",
                                                "onClick": {
                                                    "openLink": {
                                                        "url": AIRBYTE_KEY_ROTATION_RUNBOOK_URL
                                                    }
                                                },
                                                "icon": {
                                                    "iconUrl": "https://www.gstatic.com/images/branding/product/2x/docs_2020q4_48dp.png"
                                                },
                                            }
                                        ]
                                    }
                                },
                            ]
                        }
                    ],
                },
            }
        ]
    }


def notify_airbyte_key_rotation(**_):
    """
    Send a Google Chat reminder to rotate the Airbyte API key.

    Webhook URL is read from Airflow Variable GCHAT_AIRBYTE_KEY_ROTATION_WEBHOOK.
    """
    webhook_url = Variable.get(GCHAT_AIRBYTE_KEY_ROTATION_WEBHOOK, default_var=None)

    print(
        "notify_airbyte_key_rotation diagnostics: "
        f"ENVIRONMENT={os.environ.get('ENVIRONMENT', '(unset)')}, "
        f"webhook_variable_key={GCHAT_AIRBYTE_KEY_ROTATION_WEBHOOK}, "
        f"webhook_configured={'yes' if webhook_url else 'no'}"
    )

    if not webhook_url:
        print(
            f"⚠️  Airflow Variable '{GCHAT_AIRBYTE_KEY_ROTATION_WEBHOOK}' is not set. "
            "In Admin → Variables, create that key with the Google Chat incoming webhook URL."
        )
        return

    payload = _build_reminder_card()
    response = requests.post(webhook_url, json=payload)
    try:
        response.raise_for_status()
        print("✅ GChat Airbyte key rotation reminder sent successfully.")
    except Exception as e:
        print(f"❌ Failed to send GChat notification: {e}")
        raise


with DAG(
    dag_id="airflow.notify_airbyte_key_rotation",
    default_args={
        "owner": DAGOwnerEnum.DATA_PLATFORM,
        "start_date": datetime(2026, 6, 1, 0, 0, 0, tzinfo=LOCAL_TZ),
    },
    description=(
        "Daily reminder (days 20–30) to rotate the Airbyte API key. Sends a Google Chat "
        "cardsV2 message to the webhook stored in Airflow Variable "
        "GCHAT_AIRBYTE_KEY_ROTATION_WEBHOOK. "
        "Post-merge: create that Variable in Forno and Prod, then trigger manually in Forno to validate."
    ),
    schedule="0 10 20-30 * *",
    catchup=False,
    tags=["monitoring", "platform", "airbyte"],
) as dag:
    PythonOperator(
        task_id="notify_airbyte_key_rotation",
        python_callable=notify_airbyte_key_rotation,
    )
