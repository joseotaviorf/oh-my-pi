from os.path import join

import pendulum
from airflow.models import DAG
from airflow.operators.dummy_operator import DummyOperator
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services import FileService
from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback

from dags import DAG_PACKAGES_ROOT

logger = QuintoAndarLogger("dag_dependency_visualization")

DAG_ID = "airflow.dag_dependency_visualization"

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local
START_DATE = pendulum.datetime(2019, 9, 1, 0, 0, 0, tzinfo=LOCAL_TZ)


class Dag_(DummyOperator):
    ui_color = "#ec9c8d"


class SubDag_(DummyOperator):
    ui_color = "#8aa1f4"


class Task_(DummyOperator):
    ui_color = "#95b864"


@logger
def get_dependencies_from_file(file_path):
    dependencies_dict = FileService.get_dict_from_yaml_file(file_path)

    return dependencies_dict


def build_operator(dep_name, dag):
    if ":" in dep_name:
        task = Task_(dag=dag, task_id=dep_name.replace("-", "_").replace(":", "--"))
    else:
        if dep_name.count(".") < 2:
            task = Dag_(dag=dag, task_id=dep_name.replace("-", "_"))
        else:
            task = SubDag_(dag=dag, task_id=dep_name.replace("-", "_"))
    return task

opsgenie_callback = OpsgenieCallback()
dag = DAG(
    dag_id=DAG_ID,
    default_args={"owner": DAGOwnerEnum.DATA_INGESTION, "on_failure_callback": opsgenie_callback.task_failure_alert,},
    start_date=START_DATE,
    schedule_interval=None,
    
)

dependencies_file_path = join(DAG_PACKAGES_ROOT, "dependencies.yaml")
dependencies = get_dependencies_from_file(dependencies_file_path)
task_dict = {}

for dependent_dag_name in dependencies:
    if dependent_dag_name not in task_dict:
        task_dict[dependent_dag_name] = build_operator(dependent_dag_name, dag)
    for dependency_name in dependencies[dependent_dag_name]:
        if dependency_name not in task_dict:
            task_dict[dependency_name] = build_operator(dependency_name, dag)
        task_dict[dependency_name] >> task_dict[dependent_dag_name]
