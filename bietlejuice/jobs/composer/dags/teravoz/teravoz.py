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
DAG_ID = "teravoz"
MAIN_START_DATE = datetime(2019, 7, 12, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = "0 4 * * *"

ENV = Variable.get("environment")

# s3 vars
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
S3_BUCKET = "5a-datalake-forno"

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

# spark_jobs path
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/{}".format(DAG_ID)

# cluster params
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# databricks libraries
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "whl": "s3://5a-artifacts/teravoz-client/quintoandar_teravoz_client-0.1.4-py3-none-any.whl"
    }
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2019, 7, 12, 0, 0, 0),
    schedule_interval="0 5 * * *",
    catchup=False,
)


def raw_sub_dag(sub_dag_name, **kwargs):

    local_dag = BaseSubDAG(
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()

    request_api_and_load_to_raw_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id="request-api-load-to-raw",
        dag=local_dag,
        json={
            "existing_cluster_id": '{{task_instance.xcom_pull(dag_id="'
            + DAG_ID
            + '", task_ids="create_cluster", key="cluster_id")}}',
            "spark_python_task": {
                "python_file": "{}/load_teravoz_into_datalake.py".format(
                    SPARK_JOBS_PATH
                ),
                "parameters": [sub_dag_name, "raw", "{{ ds }}"],
            },
        },
    )

    create_raw_partition_task = DummyOperator(
        task_id="create_raw_partition", dag=local_dag
    )

    load_to_clean_task = DummyOperator(task_id="load_to_clean", dag=local_dag)

    create_clean_partition_task = DummyOperator(
        task_id="create_clean_partition", dag=local_dag
    )

    airflow_helpers.chain(
        request_api_and_load_to_raw_task,
        create_raw_partition_task,
        load_to_clean_task,
        create_clean_partition_task,
    )

    return local_dag


create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create_cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

# calls_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
#     dag=dag,
#     sub_dag_name='calls',
#     sub_dag_func=sub_dag
# )

calls_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag, sub_dag_name="calls", sub_dag_func=raw_sub_dag
)

# reports_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
#     dag=dag,
#     sub_dag_name='reports',
#     sub_dag_func=sub_dag
# )

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate_cluster"
)

# create_cluster_task.set_downstream([calls_sub_dag_task, queues_sub_dag_task, reports_sub_dag_task])
# terminate_cluster_task.set_upstream([calls_sub_dag_task, queues_sub_dag_task, reports_sub_dag_task])

create_cluster_task >> calls_sub_dag_task >> terminate_cluster_task
