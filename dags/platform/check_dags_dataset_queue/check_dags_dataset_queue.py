import json
import pendulum
from airflow import DAG
from airflow.configuration import conf
from airflow.models import Variable
from airflow.operators.python import PythonOperator
from airflow.utils.db import provide_session
from airflow.settings import engine
import requests
from urllib.parse import quote

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

from sqlalchemy import select, MetaData

from datetime import datetime

AIRFLOW_URL = conf.get("webserver", "base_url")
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")


def generate_card_payload(dag_dataset_map):
    """
    Generates a Google Chat cardsV2 payload.
    Input:
    {
        "dag_id_1": {"dataset_uri_1", "dataset_uri_2"},
        ...
    }
    """
    dataset_widgets = []

    for dag_id, dataset_uris in dag_dataset_map.items():
        dataset_widgets.append({"decoratedText": {"text": f"<b>🟡 DAG: {dag_id}</b>"}})
        for uri in dataset_uris:
            dataset_widgets.append(
                {
                    "decoratedText": {
                        "topLabel": f"&nbsp;&nbsp;&nbsp;&nbsp;↳ Triggered dataset: {uri}"
                    }
                }
            )

        dataset_widgets.append(
            {
                "buttonList": {
                    "buttons": [
                        {
                            "text": f"Reset Queue for {dag_id}",
                            "onClick": {
                                "openLink": {
                                    "url": f'{AIRFLOW_URL}/dags/airflow.clear_dataset_queue/trigger?dag_ids=%5B"{dag_id}"%5D'
                                }
                            },
                            "icon": {
                                "iconUrl": "https://airflow.apache.org/docs/apache-airflow/2.3.2/_images/pin_large.png"
                            },
                        }
                    ]
                }
            }
        )

    footer_section = [
        {
            "buttonList": {
                "buttons": [
                    {
                        "text": "Runbook: What should I do?",
                        "onClick": {
                            "openLink": {
                                "url": "https://docs.google.com/document/d/1dfTMqxDFV00uElPONo8a85m5dhpqnfHeBKNn48Kdcb8/edit?tab=t.0#heading=h.7mfa516ef9eo"
                            }
                        },
                        "icon": {
                            "iconUrl": "https://www.gstatic.com/images/branding/product/2x/docs_2020q4_48dp.png"
                        },
                    },
                    {
                        "text": "Reset All Queues",
                        "onClick": {
                            "openLink": {
                                "url": f"{AIRFLOW_URL}/dags/airflow.clear_dataset_queue/trigger?dag_ids={quote(json.dumps(list(dag_dataset_map.keys())))}"
                            }
                        },
                        "icon": {
                            "iconUrl": "https://airflow.apache.org/docs/apache-airflow/2.3.2/_images/pin_large.png"
                        },
                    },
                ]
            }
        }
    ]

    return {
        "cardsV2": [
            {
                "cardId": "dag_dataset_alert",
                "card": {
                    "header": {
                        "title": "🚨 DAG Dataset Queue Alert 🚨",
                        "subtitle": "The following DAGs are waiting on dataset events and may trigger outside the expected schedule",
                        "imageUrl": "https://media.licdn.com/dms/image/v2/D560BAQGNzZcOWa-Afw/company-logo_200_200/B56ZXuOuLWGoAM-/0/1743458591974/astronomer_logo?e=2147483647&v=beta&t=ubbCJrPu9UU_FD1IR4IND8n7C98VulEVuInTFpEgR_s",
                        "imageType": "CIRCLE",
                    },
                    "sections": [
                        {"widgets": dataset_widgets},
                        {"header": "Action Buttons", "widgets": footer_section},
                    ],
                },
            }
        ]
    }


with DAG(
    dag_id="airflow.check_dags_dataset_queue",
    default_args={
        "owner": DAGOwnerEnum.DATA_LIFE_CYCLE,
        "start_date": datetime(2025, 5, 16, 0, 0, 0, tzinfo=LOCAL_TZ),
    },
    description="Check if there are DAGs waiting on Dataset events and alert channels to avoid unexpected triggers.",
    schedule_interval="*/10 20-21 * * *",
    catchup=False,
    tags=["monitoring", "dataset"],
) as dag:

    @provide_session
    def check_datasets_triggering_dags(session=None, **context):
        metadata = MetaData(bind=engine)
        metadata.reflect()

        dag_queue = metadata.tables.get("dataset_dag_run_queue")
        dataset_table = metadata.tables.get("dataset")

        query = select(
            [
                dag_queue.c.target_dag_id,
                dag_queue.c.created_at,
                dataset_table.c.uri.label("dataset_uri"),
            ]
        ).select_from(
            dag_queue.join(dataset_table, dag_queue.c.dataset_id == dataset_table.c.id)
        )

        rows = session.execute(query).fetchall()
        if not rows:
            print("✅ None of the DAGs is waiting in the queue for dataset updates.")
            return

        dag_dataset_map = {}

        print(
            "🚨 DAGs currently waiting on Dataset events and possibly triggering outside the expected schedule:\n"
        )
        for row in rows:
            dag_id = row.target_dag_id
            dataset_uri = row.dataset_uri
            if not dag_id in dag_dataset_map.keys():
                dag_dataset_map[dag_id] = set()
            dag_dataset_map[dag_id].add(dataset_uri)

        for dag_id, datasets in dag_dataset_map.items():
            print(f"🟡 DAG: {dag_id}\n")
            for dataset_uri in datasets:
                print(f"   ↳ Triggered dataset: {dataset_uri}")

        webhook_url = Variable.get("DLC_GCHAT_WEBHOOK_URL", None)

        payload = generate_card_payload(dag_dataset_map)

        if webhook_url:
            print("Sending msg to GChat...")
            response = requests.post(webhook_url, json=payload)
            try:
                response.raise_for_status()
            except Exception as e:
                print(
                    f"m=send_message, msg=Gchat message was not sent, check"
                    f" the webhook url: {webhook_url}, payload: yes,"
                    f" error: {e}"
                )
        else:
            print(
                "Webhook token DLC_GCHAT_WEBHOOK_URL is not configured in Airflow Variables."
            )

    task_check = PythonOperator(
        task_id="check_dataset_dag_queued",
        python_callable=check_datasets_triggering_dags,
    )
