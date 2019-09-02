from datetime import datetime

from bietlejuice.jobs.composer.base.airflow.base_dag import BaseDAG
from bietlejuice.jobs.composer.base.airflow.base_sub_dag import BaseSubDAG

from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from airflow.operators.dummy_operator import DummyOperator
import airflow.utils.helpers as airflow_helpers

# dag params
DAG_ID = "bietlejuice.teravoz"
MAIN_START_DATE = datetime(2019, 7, 12, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = "0 4 * * *"

ENV = Variable.get("environment")

# s3 vars
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

# spark_jobs path
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/teravoz"

# cluster params
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# databricks libraries
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "whl": "s3://5a-artifacts/tapioca-wrapper/tapioca_wrapper-quintoandar_1.5.1-py3-none-any.whl"
    },
    {
        "whl": "s3://5a-artifacts/teravoz-client/quintoandar_teravoz_client-0.1.5-py3-none-any.whl"
    },
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=False,
)


def raw_tasks(sub_dag_name, local_dag):

    request_api_and_load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="request-api-load-to-raw",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/load_teravoz_into_datalake.py".format(
                    SPARK_JOBS_PATH
                ),
                "parameters": [sub_dag_name, "{{ ds }}", ENV],
            }
        },
    )

    create_raw_partition_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-raw-partition",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/create_external_table.py".format(SPARK_JOBS_PATH),
                "parameters": [sub_dag_name, "raw", "{{ ds }}", ENV],
            }
        },
    )

    raw_tasks_list = [request_api_and_load_to_raw_task, create_raw_partition_task]
    return raw_tasks_list


def clean_tasks(sub_dag_name, local_dag):

    clean_tasks_list = []

    load_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="move-data-to-clean",
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": "{}/load_data_to_clean.py".format(SPARK_JOBS_PATH),
                "parameters": [sub_dag_name, "{{ ds }}", ENV],
            }
        },
    )

    clean_tasks_list.append(load_to_clean_task)

    create_clean_partition_task = DummyOperator(
        task_id="create-clean-partition", dag=local_dag
    )

    clean_tasks_list = [load_to_clean_task, create_clean_partition_task]
    return clean_tasks_list


def sub_dag(sub_dag_name):

    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    list_tasks = raw_tasks(sub_dag_name, local_dag)
    list_tasks += clean_tasks(sub_dag_name, local_dag)

    airflow_helpers.chain(
        list_tasks[0],  # request_api_and_load_to_raw_task
        list_tasks[1],  # create_raw_partition_task
        list_tasks[2],  # load_to_clean_task
        list_tasks[3],  # create_clean_partition_task
    )

    return local_dag


def raw_sub_dag(sub_dag_name):

    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    list_tasks = raw_tasks(sub_dag_name, local_dag)
    airflow_helpers.chain(
        list_tasks[0],  # request_api_and_load_to_raw_task
        list_tasks[1],  # create_raw_partition_task
    )

    return local_dag


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)


def clean_sub_dag(sub_dag_name):

    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    list_tasks = clean_tasks(sub_dag_name, local_dag)

    airflow_helpers.chain(
        list_tasks[0],  # load_to_clean_task
        list_tasks[1],  # create_clean_partition_task
    )
    return local_dag


calls_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="calls", sub_dag_func=sub_dag
)
queues_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="queues", sub_dag_func=sub_dag
)
peers_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="peers", sub_dag_func=sub_dag
)
ddrs_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="ddrs", sub_dag_func=sub_dag
)
report_agent_performance_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="report-agent-performance", sub_dag_func=raw_sub_dag
)
report_queue_stats_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="report-queue-stats", sub_dag_func=sub_dag
)
report_agent_status_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="report-agent-status", sub_dag_func=raw_sub_dag
)
report_agents_per_queue_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="report-agents-queue-metrics", sub_dag_func=clean_sub_dag
)
terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task.set_downstream(
    [calls_sub_dag_task, queues_sub_dag_task, peers_sub_dag_task, ddrs_sub_dag_task]
)
queues_sub_dag_task.set_downstream(
    [
        report_agent_performance_sub_dag_task,
        report_queue_stats_sub_dag_task,
        report_agent_status_sub_dag_task,
    ]
)
report_agents_per_queue_sub_dag_task.set_upstream(
    [report_agent_performance_sub_dag_task, report_agent_status_sub_dag_task]
)
terminate_cluster_task.set_upstream(
    [
        calls_sub_dag_task,
        report_queue_stats_sub_dag_task,
        report_agents_per_queue_sub_dag_task,
        peers_sub_dag_task,
        ddrs_sub_dag_task,
    ]
)
