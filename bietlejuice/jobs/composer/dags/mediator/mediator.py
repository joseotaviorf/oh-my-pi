from datetime import datetime, date

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_dag_mediator import (
    QuintoAndarShortCircuitExternalSensor,
    QuintoAndarCustomTriggerDagOperator,
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


def extract_dependencies():
    dependencies_file_path = COMPOSER_DAGS_PATH + "/dependencies.yaml"
    dependencies_dict = FileService.get_dict_from_yaml_file(dependencies_file_path)

    validate_dependencies(dependencies_dict)

    return dependencies_dict


def extract_skip_list():
    mediator_skip_list = Variable.get(
        "MEDIATOR_SKIP_LIST", deserialize_json=True, default_var={}
    )
    force_skip_list = []
    if "dags" in mediator_skip_list and mediator_skip_list["dags"]:
        for dag_id, skip_date in mediator_skip_list["dags"].items():
            skip_date = datetime.strptime(skip_date, "%Y-%m-%d").date()
            if date.today() == skip_date:
                force_skip_list.append(dag_id)

    return force_skip_list


# Define tasks
mediator_dag = DAG(
    dag_id="airflow.mediator",
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
To force some temporary DAG skipping, use this [variable](/admin/variable/?flt1_0=MEDIATOR_SKIP_LIST)

Docs:

- [check-dependencies](https://github.com/quintoandar/airflow-plugins/blob/master/quintoandar_airflow_plugins/dag_mediator_plugin.md) sensor references
- Mediator [directory](https://drive.google.com/drive/folders/1fIJBKVw4Jjojb9eLu8AHlzmFHBowRRGu) with docs and references
"""

dependencies_dict = extract_dependencies()
sensor_task = QuintoAndarShortCircuitExternalSensor(
    dag=mediator_dag,
    task_id="check-dependencies",
    dependencies=dependencies_dict,
    skip_list=extract_skip_list(),
    allow_rerun=False,
    retries=0,
)

trigger_dependent_dags_list = []
for dependent_dag_id in dependencies_dict.keys():
    trigger_dependent_dag_id_task = QuintoAndarCustomTriggerDagOperator(
        dag=mediator_dag, dependent_dag_id=dependent_dag_id
    )
    trigger_dependent_dags_list.append(trigger_dependent_dag_id_task)

sensor_task.set_downstream(trigger_dependent_dags_list)
