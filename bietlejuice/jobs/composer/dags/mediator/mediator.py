from datetime import datetime

from airflow.models import DAG
from airflow.operators.dagrun_operator import TriggerDagRunOperator
from airflow.operators.quintoandar_dag_mediator import (
    QuintoAndarShortCircuitExternalSensor,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags import COMPOSER_DAGS_PATH
from bietlejuice.jobs.composer.services import FileService


def validate_dependencies(dependencies_list):
    if not len(dependencies_list):
        raise RuntimeError(
            "m=check_if_can_dag_run, msg=No dependencies found in YAML file. "
            "Stoping the DAG."
        )


dependencies_file_path = COMPOSER_DAGS_PATH + "/dependencies.yaml"
dependencies_dict = FileService.get_dict_from_yaml_file(dependencies_file_path)

validate_dependencies(dependencies_dict)

# Define tasks
mediator_dag = DAG(
    dag_id="bietlejuice.mediator",
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2020, 5, 8, 0, 0, 0),
    schedule_interval="0,30 * * * *",
)
mediator_dag.doc_md = """
#### Mediator DAG
This DAG checks for dependencies completion and triggers the dependents DAG in
the pipeline.

Docs:
- [short-circuit](https://github.com/quintoandar/airflow-plugins/blob/master/quintoandar_airflow_plugins/dag_mediator_plugin.md)
- Mediator [directory](https://drive.google.com/drive/folders/1fIJBKVw4Jjojb9eLu8AHlzmFHBowRRGu) with docs and references
"""

sensor_task = QuintoAndarShortCircuitExternalSensor(
    dag=mediator_dag, task_id="short-circuit", dependencies=dependencies_dict
)

trigger_dependent_dags_list = []
for dependent_dag_id in dependencies_dict.keys():
    task_id = dependent_dag_id.replace(".", "-").replace("_", "-")
    trigger_dependent_dag_id_task = TriggerDagRunOperator(
        dag=mediator_dag,
        task_id=f"trigger-{task_id}-dag",
        trigger_dag_id=dependent_dag_id,
        execution_date="{{ execution_date }}",  # the DAG execution date
    )
    trigger_dependent_dags_list.append(trigger_dependent_dag_id_task)

sensor_task.set_downstream(trigger_dependent_dags_list)
