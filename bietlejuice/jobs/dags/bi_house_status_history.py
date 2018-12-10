from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.house_status_history import HouseStatusHistory, HouseStatusFullHistory

# env vars
env.set_airflow_var_to_local_env('BI_ODS', 'EBDB')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_ID = 'bi-house-status-history'
MAIN_START_DATE = datetime(2018, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('30 0 * * *')


# functions
def execute_class_method(class_, method, method_kwargs):
    class__ = class_()
    getattr(class__, method)(**method_kwargs)


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
    catchup=False
)


def house_status_history_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    load_data_into_ods_stg_task = BaseDAG.build_quintoandar_python_operator(
        task_id='load_data_into_ods_stg',
        python_callable=execute_class_method,
        dag=local_dag,
        op_kwargs={
            'class_': HouseStatusHistory,
            'method': 'load_data_into_ods_stg'
        }
    )

    delete_duplicated_entries_task = BaseDAG.build_quintoandar_python_operator(
        task_id='delete_duplicated_entries',
        python_callable=execute_class_method,
        dag=local_dag,
        op_kwargs={
            'class_': HouseStatusHistory,
            'method': 'delete_duplicated_entries'
        }
    )

    load_data_into_ods_task = BaseDAG.build_quintoandar_python_operator(
        task_id='load_data_into_ods',
        python_callable=execute_class_method,
        dag=local_dag,
        op_kwargs={
            'class_': HouseStatusHistory,
            'method': 'load_data_into_ods'
        }
    )

    load_data_into_data_lake_task = BaseDAG.build_quintoandar_python_operator(
        task_id='load_data_into_data_lake',
        python_callable=execute_class_method,
        dag=local_dag,
        op_kwargs={
            'class_': HouseStatusHistory,
            'method': 'load_data_into_data_lake',
            'method_kwargs': {'s3_bucket': s3_bucket}
        }
    )

    airflow_helpers.chain(
        load_data_into_ods_stg_task,
        delete_duplicated_entries_task,
        load_data_into_ods_task,
        load_data_into_data_lake_task
    )

    return local_dag


def house_status_full_history_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    load_data_into_ods_task = BaseDAG.build_quintoandar_python_operator(
        task_id='load_data_into_ods',
        python_callable=execute_class_method,
        dag=local_dag,
        op_kwargs={
            'class_': HouseStatusFullHistory,
            'method': 'load_data_into_ods'
        }
    )

    load_data_into_data_lake_task = BaseDAG.build_quintoandar_python_operator(
        task_id='load_data_into_data_lake',
        python_callable=execute_class_method,
        dag=local_dag,
        op_kwargs={
            'class_': HouseStatusFullHistory,
            'method': 'load_data_into_data_lake',
            'method_kwargs': {'s3_bucket': s3_bucket}
        }
    )

    airflow_helpers.chain(
        load_data_into_ods_task,
        load_data_into_data_lake_task
    )

    return local_dag


# operators
house_status_history_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='house_status_history',
    sub_dag_func=house_status_history_sub_dag,
)

house_status_full_history_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='house_status_full_history',
    sub_dag_func=house_status_full_history_sub_dag,
)

# TODO: add unit tests
