from airflow.models import DAG, DagBag, DagModel
from airflow.operators.python_operator import PythonOperator
from airflow.exceptions import AirflowSkipException

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

import boto3
from datetime import datetime
import json


DAG_ID = "bietlejuice.migration_assets"


def print_current_state(**kwargs):
    flag = kwargs.get("dag_run").conf.get("save_current_state", False)

    if not flag:
        raise AirflowSkipException(
            "msg=save_current_state is not enabled, skipping this task..."
        )  # Faz a tarefa ser marcada como skipped

    dag_bag = DagBag(store_serialized_dags=True, include_examples=False)
    dag_bag.collect_dags_from_db()

    dag_state = {}

    for dag_id, dag in dag_bag.dags.items():
        dag_state[dag_id] = True if dag.is_paused else False

    json_data = json.dumps(dag_state, indent=4)
    print(json_data)


def pause_all_dags(**kwargs):
    flag = kwargs.get("dag_run").conf.get("pause_all_dags", False)

    if not flag:
        raise AirflowSkipException(
            "msg=pause_all_dags is not enabled, skipping this task..."
        )

    dag_bag = DagBag(store_serialized_dags=True, include_examples=False)
    dag_bag.collect_dags_from_db()
    for dag_id, dag in dag_bag.dags.items():
        dag_model = DagModel.get_dagmodel(dag_id)
        if dag_model and not dag.is_paused:
            dag_model.set_is_paused(is_paused=True)
            print(f"msg=Pausing {dag_id}")


def set_state(**kwargs):
    dags_state = kwargs.get("dag_run").conf.get("state", None)

    if not dags_state:
        raise AirflowSkipException("msg=state is not enabled, skipping this task...")

    for dag_id, state in dags_state.items():
        dag_model = DagModel.get_dagmodel(dag_id)
        if dag_model:
            dag_model.set_is_paused(is_paused=state)
            print(f"msg=Setting {dag_id} as {state}")
        else:
            print(f"msg=DAG with id `{dag_id}` not found.")


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_INGESTION,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2025, 2, 25),
    schedule_interval=None,
    doc_md="This DAG is used to generate assets to Astronomer migration.",
)

print_current_state = PythonOperator(
    task_id=f"print_current_state",
    dag=dag,
    python_callable=print_current_state,
    provide_context=True,
)

pause_all_dags = PythonOperator(
    task_id=f"pause_all_dags",
    dag=dag,
    python_callable=pause_all_dags,
    provide_context=True,
)

set_state = PythonOperator(
    task_id=f"set_state", dag=dag, python_callable=set_state, provide_context=True
)
