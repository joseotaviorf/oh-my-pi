from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.crm.task_status_histories import CRMTaskStatusHistories

# env vars
env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
mongo_client_uri = env.get_airflow_env_var('MONGODB_CRM_URI')

MAIN_DAG_ID = 'bi-crm-load-task-resolution-history-reprocess'
MAIN_START_DATE = datetime(2015, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 0 * * *')


# functions
def exec_task_status_histories_method(method, **kwargs):
    crm = CRMTaskStatusHistories(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    getattr(crm, method)(**kwargs)


# dags
main_dag = DAG(
    dag_id=MAIN_DAG_ID,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    orientation='TB',
    catchup=True
)


def incremental_clean_sub_dag(sub_dag_name, python_exec, python_method, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    move_to_clean_task = BaseDAG.build_python_operator(
        task_id='move_to_clean',
        python_callable=python_exec,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'method': python_method['move_to_clean']
        }
    )

    upsert_clean_partitions_task = BaseDAG.build_python_operator(
        task_id='upsert_clean_partition',
        python_callable=python_exec,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'clean',
            'method': python_method['upsert_clean_partition']
        }
    )

    airflow_helpers.chain(
        move_to_clean_task,
        upsert_clean_partitions_task
    )

    return local_dag


# operators
clean_task_resolution_history_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='incremental_load_clean_task_resolution_history_table',
    python_exec=exec_task_status_histories_method,
    python_method={
        'move_to_clean': 'move_tasks_resolution_history_to_clean',
        'upsert_clean_partition': 'upsert_tasks_resolution_history_partition'
    },
    sub_dag_func=incremental_clean_sub_dag,
)
