import logging
from datetime import datetime

import pendulum
from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator

DAG_NAME = "reset_datasets"


def reset_dataset_queues(**_kwargs):
    from airflow.models.dataset import DatasetDagRunQueue, DatasetModel
    from airflow.utils.db import create_session
    from sqlalchemy import delete, func, select

    logging.info("Starting reset of DatasetDagRunQueue")
    try:
        with create_session() as session:
            stmt = select(
                DatasetDagRunQueue.target_dag_id,
                DatasetModel.uri,
                DatasetDagRunQueue.created_at,
            ).join(
                DatasetModel,
                DatasetDagRunQueue.dataset_id == DatasetModel.id,
            )
            rows = session.execute(stmt).all()
            logging.info(f"DatasetDagRunQueue snapshot: {len(rows)} entries")
            for target_dag_id, uri, created_at in rows:
                logging.info(
                    f"  queue entry: target_dag_id={target_dag_id}, "
                    f"dataset_uri={uri}, created_at={created_at}"
                )

            result = session.execute(delete(DatasetDagRunQueue))
            logging.info(f"Deleted {result.rowcount} rows from DatasetDagRunQueue")

            remaining = session.execute(
                select(func.count()).select_from(DatasetDagRunQueue)
            ).scalar()
            logging.info(f"DatasetDagRunQueue remaining rows: {remaining}")
            if remaining != 0:
                logging.warning(
                    f"Expected 0 rows in DatasetDagRunQueue after "
                    f"delete, found {remaining}"
                )
    except Exception as e:
        logging.error(f"Failed to reset DatasetDagRunQueue: {e}")
        raise
    return f"OK — deleted {result.rowcount} rows"


def archive_and_reset_dataset_events(**_kwargs):
    from airflow.models.dataset import DatasetEvent, DatasetModel
    from airflow.utils.db import create_session
    from sqlalchemy import delete, func, select

    logging.info("Starting archive and reset of DatasetEvent")
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
                logging.info(f"  dataset_uri={uri}, events={count}")

            rows_stmt = (
                select(
                    DatasetEvent.id,
                    DatasetModel.uri,
                    DatasetEvent.source_dag_id,
                    DatasetEvent.source_task_id,
                    DatasetEvent.source_run_id,
                    DatasetEvent.source_map_index,
                    DatasetEvent.extra,
                    DatasetEvent.timestamp,
                )
                .select_from(DatasetEvent)
                .outerjoin(
                    DatasetModel,
                    DatasetEvent.dataset_id == DatasetModel.id,
                )
            )
            raw_events = session.execute(rows_stmt).all()
            events = [
                {
                    "id": row.id,
                    "uri": row.uri,
                    "source_dag_id": row.source_dag_id,
                    "source_task_id": row.source_task_id,
                    "source_run_id": row.source_run_id,
                    "source_map_index": row.source_map_index,
                    "extra": row.extra,
                    "timestamp": row.timestamp.isoformat()
                    if hasattr(row.timestamp, "isoformat")
                    else str(row.timestamp),
                }
                for row in raw_events
            ]

            if not events:
                logging.info("No events to archive or delete")
                return "OK — 0 events to archive"

            from bietlejuice.services.dataset_service import DatasetService

            object_key = DatasetService.archive_dataset_events_to_s3(events)
            logging.info(f"Archived {len(events)} events to s3 object {object_key}")

            archived_ids = [row.id for row in raw_events]
            chunk_size = 500
            total_deleted = 0
            for i in range(0, len(archived_ids), chunk_size):
                chunk = archived_ids[i : i + chunk_size]
                res = session.execute(
                    delete(DatasetEvent).where(DatasetEvent.id.in_(chunk))
                )
                total_deleted += res.rowcount
            logging.info(f"Deleted {total_deleted} rows from DatasetEvent")

            remaining = session.execute(
                select(func.count()).select_from(DatasetEvent)
            ).scalar()
            logging.info(f"DatasetEvent remaining rows: {remaining}")
            if remaining != 0:
                logging.info(
                    f"DatasetEvent has {remaining} unarchived rows remaining (new events created during archive)"
                )
    except Exception as e:
        logging.error(f"Failed to reset DatasetEvent: {e}")
        raise

    return f"OK — archived {len(events)} events to {object_key} and deleted {total_deleted} rows"


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
        python_callable=archive_and_reset_dataset_events,
    )
    reset_queues_task >> reset_events_task
