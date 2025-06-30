from airflow.operators.python_operator import PythonOperator
from airflow.models import DAG
from airflow.models.param import Param
from airflow.models.taskinstancekey import TaskInstanceKey
from airflow.datasets import Dataset
from airflow.utils import timezone
from airflow.utils.session import NEW_SESSION, provide_session
from airflow.datasets.manager import dataset_manager
from datetime import datetime
import logging
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from airflow.api_connexion.schemas.dataset_schema import (
    dataset_event_schema,
)
from airflow.datasets import Dataset

from airflow.utils.session import NEW_SESSION, provide_session
from sqlalchemy.orm.session import Session


DAG_ID = "bietlejuice.trigger_datasets"
@provide_session
def trigger_dataset_based_on_input(session: Session = NEW_SESSION, **context):
    params = context["dag_run"].conf or {}

    source_dag_id = params.get("source_dag_id")
    source_task_id = params.get("source_task_id")
    source_run_id = params.get("source_run_id") 
    is_first_run = params.get("is_first_run_of_date", False) 

    if not (source_dag_id and source_task_id and source_run_id):
        raise ValueError("dag_id, task_id and source_run_id must be provided in dag trigger forms")
    
    logging.info(""f"Triggering dataset for DAG: {source_dag_id}, Task: {source_task_id}, Source Run ID: {source_run_id}")
     
    dataset_uri = f"{source_dag_id}:{source_task_id}"
    dataset_uri_first_run = f"{dataset_uri}:first-run-of-day"
    alias_uri = f"{dataset_uri}:alias"
    list_of_datasets = [dataset_uri]
    events = []

    if is_first_run:
        logging.info(f"First run detected, adding dataset URI: {dataset_uri_first_run} to the list")
        list_of_datasets.append(dataset_uri_first_run)
        
    for uri in list_of_datasets:
        logging.info(f"Triggering dataset event for URI: {uri}")
        
        timestamp = timezone.utcnow()
        extra = {}
        
        dataset_event = dataset_manager.register_dataset_change(
            task_instance=TaskInstanceKey(
                dag_id=source_dag_id,
                task_id=source_task_id,
                run_id=source_run_id,
            ),
            dataset=Dataset(uri),
            timestamp=timestamp,
            extra=extra,
            session=session,
            source_alias_names={alias_uri},
        )
        if dataset_event:
            event = dataset_event_schema.dump(dataset_event)
            events.append(event)
    return events

def get_trigger_form_param() -> dict:
    return {
        "source_dag_id": Param(
            default="",
            type="string",
            description_md="DAG ID of the dataset producer from DAG A",
        ),
        "source_task_id": Param(
            default="",
            type="string",
            description_md="Task ID of the dataset producer from DAG A",
        ),
        "source_run_id": Param(
            default="",
            type="string",
            description_md="Simulated run ID from DAG A",
        ),
        "is_first_run_of_date": Param(
            default="",
            type="boolean",
            description_md="Indicates if this is the first run of the day for the dataset",
        )
    }


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_LIFE_CYCLE, 
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2025, 6, 9),
    schedule_interval=None,
    doc_md="Trigger datasets manually based on user input.",
    params=get_trigger_form_param(),
)

trigger_task = PythonOperator(
    task_id="trigger_dataset_based_on_input",
    python_callable=trigger_dataset_based_on_input,
    provide_context=True,
    dag=dag
)
