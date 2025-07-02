import pendulum
from airflow.operators.python_operator import PythonOperator
from airflow.models import DAG
from datetime import datetime


def reset_dataset_queues(**kwargs):
    params = kwargs.get("params", {})
    print("Resetting for ", params)
    from airflow.utils.db import create_session
    from sqlalchemy import delete, select
    from airflow.models.dataset import DatasetDagRunQueue

    with create_session() as session:
        session.execute(delete(DatasetDagRunQueue))
    return "OK"


def reset_datasets(**kwargs):
    params = kwargs.get("params", {})
    print("Resetting for ", params)
    from airflow.utils.db import create_session
    from sqlalchemy import delete
    from airflow.models.dataset import DatasetEvent

    with create_session() as session:
        session.execute(delete(DatasetEvent))
    return "OK"


with DAG(
    "reset_datasets",
    start_date=datetime(
        2025, 7, 1, 0, 0, 0, tzinfo=pendulum.timezone("America/Sao_Paulo")
    ),
    schedule_interval="45 20 * * *",
    catchup=False,
    doc_md="docs",
) as dag:
    pythonOperator = PythonOperator(
        task_id="reset_dataset_queues", python_callable=reset_dataset_queues
    )
    pythonOperator_2 = PythonOperator(
        task_id="reset_dataset_events", python_callable=reset_datasets
    )
    pythonOperator >> pythonOperator_2
