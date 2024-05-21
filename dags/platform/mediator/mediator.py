from datetime import datetime, date, timedelta

from airflow.models import DAG, Variable
from dag_mediator_plugin import (
    QuintoAndarShortCircuitExternalSensor,
    QuintoAndarCustomTriggerDagOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from bietlejuice.base.dependencies.bietlejuice_redundant_dependency_finder import (
    BietlejuiceRedundantDependencyFinder,
)


def validate_dependencies(dependencies_list):
    if not len(dependencies_list):
        raise RuntimeError(
            "m=check_if_can_dag_run, msg=No dependencies found in YAML file. "
            "Stoping the DAG."
        )


def extract_dependencies():
    dependencies_dict = BietlejuiceDependencyHelper.read_dependencies()
    redundancy_finder = BietlejuiceRedundantDependencyFinder(dependencies_dict)
    dependencies_dict = redundancy_finder.remove_all_redundancies()
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
DAG_NAME = "mediator"
DAG_ID = f"airflow.{DAG_NAME}"
mediator_dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2020, 5, 8, 0, 0, 0),
    schedule_interval="*/10 * * * *",
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=Variable.get("DOC_MD_BASE_URL"), dag_id=DAG_ID
    ),
    dagrun_timeout=timedelta(minutes=9),
)

dependencies_dict = extract_dependencies()
sensor_task = QuintoAndarShortCircuitExternalSensor(
    dag=mediator_dag,
    task_id="check-dependencies",
    dependencies=dependencies_dict,
    skip_list=extract_skip_list(),
    allow_rerun=False,
    retries=0,
    read_dags_from_db=True,
)

trigger_dependent_dags_list = []
for dependent_dag_id in dependencies_dict.keys():
    trigger_dependent_dag_id_task = QuintoAndarCustomTriggerDagOperator(
        dag=mediator_dag, dependent_dag_id=dependent_dag_id
    )
    trigger_dependent_dags_list.append(trigger_dependent_dag_id_task)

sensor_task.set_downstream(trigger_dependent_dags_list)
