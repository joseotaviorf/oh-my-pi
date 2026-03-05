import logging
from datetime import datetime

import pendulum
from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

DAG_NAME = "reset_datasets"


def reset_dataset_queues(**kwargs):
    from airflow.models.dataset import DatasetDagRunQueue, DatasetModel
    from airflow.utils.db import create_session
    from sqlalchemy import delete, func, select

    logging.info("Starting reset of DatasetDagRunQueue")
    try:
        with create_session() as session:
            stmt = (
                select(
                    DatasetDagRunQueue.target_dag_id,
                    DatasetModel.uri,
                    DatasetDagRunQueue.created_at,
                )
                .join(
                    DatasetModel,
                    DatasetDagRunQueue.dataset_id == DatasetModel.id,
                )
            )
            rows = session.execute(stmt).all()
            logging.info(
                f"DatasetDagRunQueue snapshot: {len(rows)} entries"
            )
            for target_dag_id, uri, created_at in rows:
                logging.info(
                    f"  queue entry: target_dag_id={target_dag_id}, "
                    f"dataset_uri={uri}, created_at={created_at}"
                )

            result = session.execute(delete(DatasetDagRunQueue))
            logging.info(
                f"Deleted {result.rowcount} rows from DatasetDagRunQueue"
            )

            remaining = session.execute(
                select(func.count()).select_from(DatasetDagRunQueue)
            ).scalar()
            logging.info(
                f"DatasetDagRunQueue remaining rows: {remaining}"
            )
            if remaining != 0:
                logging.warning(
                    f"Expected 0 rows in DatasetDagRunQueue after "
                    f"delete, found {remaining}"
                )
    except Exception as e:
        logging.error(f"Failed to reset DatasetDagRunQueue: {e}")
        raise
    return f"OK — deleted {result.rowcount} rows"


def reset_dataset_events(**kwargs):
    from airflow.models.dataset import DatasetEvent, DatasetModel
    from airflow.utils.db import create_session
    from sqlalchemy import delete, func, select

    logging.info("Starting reset of DatasetEvent")
    try:
        with create_session() as session:
            stmt = (
                select(
                    DatasetModel.uri,
                    func.count().label("event_count"),
                )
                .select_from(DatasetEvent)
                .join(
                    DatasetModel,
                    DatasetEvent.dataset_id == DatasetModel.id,
                )
                .group_by(DatasetModel.uri)
                .order_by(func.count().desc())
            )
            dataset_counts = session.execute(stmt).all()
            total = sum(c for _, c in dataset_counts)
            logging.info(
                f"DatasetEvent snapshot: "
                f"{len(dataset_counts)} distinct datasets, "
                f"{total} total events"
            )
            for uri, count in dataset_counts:
                logging.info(
                    f"  dataset_uri={uri}, events={count}"
                )

            result = session.execute(delete(DatasetEvent))
            logging.info(
                f"Deleted {result.rowcount} rows from DatasetEvent"
            )

            remaining = session.execute(
                select(func.count()).select_from(DatasetEvent)
            ).scalar()
            logging.info(
                f"DatasetEvent remaining rows: {remaining}"
            )
            if remaining != 0:
                logging.warning(
                    f"Expected 0 rows in DatasetEvent after "
                    f"delete, found {remaining}"
                )
    except Exception as e:
        logging.error(f"Failed to reset DatasetEvent: {e}")
        raise

    return f"OK — deleted {result.rowcount} rows"


with DAG(
    "reset_datasets",
    start_date=datetime(
        2025, 7, 1, 0, 0, 0, tzinfo=pendulum.timezone("America/Sao_Paulo")
    ),
    schedule_interval="55 20 * * *",
    catchup=False,
    doc_md="docs",
) as dag:
    reset_queues_task = PythonOperator(
        task_id="reset_dataset_queues",
        python_callable=reset_dataset_queues,
    )
    reset_events_task = PythonOperator(
        task_id="reset_dataset_events",
        python_callable=reset_dataset_events,
    )
    reset_queues_task >> reset_events_task
