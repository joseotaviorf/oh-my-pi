from airflow import DAG
from airflow.decorators import task
from airflow.utils.dates import days_ago
from airflow.models.dataset import DatasetDagRunQueue
from airflow.models import DagBag, Param
from airflow.exceptions import AirflowFailException
from airflow.utils.session import provide_session
from airflow.utils.state import DagRunState
from airflow.utils.types import DagRunType
from airflow.timetables.base import DataInterval
from datetime import datetime
import logging

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

DAG_NAME = 'clear_dataset_queue'
DAG_ID = f'airflow.{DAG_NAME}'
default_args = {
    'owner': DAGOwnerEnum.DATA_LIFE_CYCLE,
}

@provide_session
def clear_dataset_data(dag: DAG, execution_date: datetime, session=None):
    if not dag:
        raise AirflowFailException("Missing DAG")

    logging.info(f"Clearing dataset events for DAG ID: {dag.dag_id}")

    # Delete dataset dag run queue entries
    deleted_queue_entries = session.query(DatasetDagRunQueue).filter(
        DatasetDagRunQueue.target_dag_id == dag.dag_id
    ).delete()
    logging.info(f"Deleted {deleted_queue_entries} dataset dag run queue entries for DAG ID: {dag.dag_id}")
    
    # Create a sucessful dataset-triggered DAG run
    # Clearing the queue is not enough: Airflow queries for all dataset events after the last successful dataset-triggered run
    dag_run = dag.create_dagrun(
        state=DagRunState.SUCCESS,
        execution_date=execution_date,
        start_date=execution_date,
        run_type=DagRunType.DATASET_TRIGGERED,
        session=session,
        data_interval=DataInterval(execution_date, execution_date),
    )
    logging.info(f"Created a successful dataset-triggered DAG run for DAG ID: {dag.dag_id}")

    dag_run.note = "This DAG run was created automatically by the DAG airflow.clear_dataset_queue as a way "\
                   "to make sure that dataset events from before this run don't affect future DAG runs."
    session.add(dag_run)
    logging.info(f"Updated DAG run note for DAG ID: {dag.dag_id}")

    session.commit()

with DAG(
    dag_id=DAG_ID,
    default_args=default_args,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME),
    schedule_interval=None,
    start_date=days_ago(1),
    catchup=False,
    params={
        "dag_ids": Param(
            [],
            type="array",
            description=(
                "DAG IDs whose dataset queue should be cleared. "
                "Only dataset-triggered DAGs are relevant here. "
                "To find them, go to Airflow UI → Datasets and look for DAGs "
                "listed as consumers of the dataset you want to reset."
            ),
            items={"type": "string"},
        )
    }
) as dag:

    @task()
    def run_clear_dataset_events_from_queue(**context):
        dag_ids = context['params'].get('dag_ids')
        if not dag_ids:
            raise AirflowFailException("No DAG IDs provided in params")
        
        dag_bag = DagBag(store_serialized_dags=True, include_examples=False)
        dag_bag.collect_dags_from_db()

        for dag_id in dag_ids:
            if dag_id not in dag_bag.dags:
                raise AirflowFailException(f"DAG ID {dag_id} not found in the DAG bag")
            clear_dataset_data(dag_bag.dags[dag_id], execution_date=context['execution_date'])

    run_clear_dataset_events_from_queue()