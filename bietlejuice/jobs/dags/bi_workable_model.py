import json
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.workable import WorkableFactory, Workable

# env vars
env.set_airflow_var_to_local_env('BI_DW')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
workable_auth = json.loads(env.get_airflow_env_var('WORKABLE_AUTHORIZATION'))

MAIN_DAG_ID = 'bi-workable-model'
MAIN_START_DATE = datetime(2018, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')


# functions
def extract_and_load_data(_class):
    workable = WorkableFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        url_prefix=workable_auth['url_prefix'],
        access_token=workable_auth['access_token']
    )
    _data = workable.extract_data()
    workable.save_into_s3_raw(json_list=_data)


def exec_class_method(_class, method):
    workable = WorkableFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        url_prefix=workable_auth['url_prefix'],
        access_token=workable_auth['access_token']
    )

    getattr(workable, method)()


def exec_workable_method(method):
    workable = Workable(
        s3_bucket=s3_bucket,
        url_prefix=workable_auth['url_prefix'],
        access_token=workable_auth['access_token']
    )

    getattr(workable, method)()


def move_fact_to_dw():
    workable = Workable(
        s3_bucket=s3_bucket,
        url_prefix=workable_auth['url_prefix'],
        access_token=workable_auth['access_token']
    )

    workable._move_to_dw(Workable.TABLE_NAMES['fact'])


def delete_staging_fact_entries():
    workable = Workable(
        s3_bucket=s3_bucket,
        url_prefix=workable_auth['url_prefix'],
        access_token=workable_auth['access_token']
    )

    workable._delete_staging_entries(Workable.TABLE_NAMES['fact'])


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


def class_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_task = BaseDAG.build_quintoandar_python_operator(
        task_id='extract_data_into_raw',
        python_callable=extract_and_load_data,
        dag=local_dag,
        op_kwargs={
            '_class': kwargs['_class']
        }
    )

    move_to_clean_task = BaseDAG.build_quintoandar_python_operator(
        task_id='move_to_clean',
        python_callable=exec_class_method,
        dag=local_dag,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'move_to_clean'
        }
    )

    move_to_staging_dim_task = BaseDAG.build_quintoandar_python_operator(
        task_id='move_to_staging_dim',
        python_callable=exec_class_method,
        dag=local_dag,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'move_to_staging_dim'
        }
    )

    move_dim_to_dw_task = BaseDAG.build_quintoandar_python_operator(
        task_id='move_dim_to_dw',
        python_callable=exec_class_method,
        dag=local_dag,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'move_dim_to_dw'
        }
    )

    delete_dim_staging_entries_task = BaseDAG.build_quintoandar_python_operator(
        task_id='delete_dim_staging_entries',
        python_callable=exec_class_method,
        dag=local_dag,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'delete_dim_staging_entries'
        }
    )

    airflow_helpers.chain(
        extract_and_load_task,
        move_to_clean_task,
        move_to_staging_dim_task,
        move_dim_to_dw_task,
        delete_dim_staging_entries_task
    )

    return local_dag


def fact_load_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    move_to_staging_fact_task = BaseDAG.build_quintoandar_python_operator(
        task_id='move_to_staging_fact',
        python_callable=exec_workable_method,
        dag=local_dag,
        op_kwargs={
            'method': '_move_to_staging_fact'
        }
    )

    move_to_dw_task = BaseDAG.build_quintoandar_python_operator(
        task_id='move_to_dw',
        python_callable=move_fact_to_dw,
        dag=local_dag
    )

    delete_staging_entries_task = BaseDAG.build_quintoandar_python_operator(
        task_id='delete_staging_entries',
        python_callable=delete_staging_fact_entries,
        dag=local_dag
    )

    airflow_helpers.chain(
        move_to_staging_fact_task,
        move_to_dw_task,
        delete_staging_entries_task
    )

    return local_dag


# operators
members_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name=Workable.TypeEnum.MEMBERS.value,
    sub_dag_func=class_sub_dag,
    _class=Workable.TypeEnum.MEMBERS
)

jobs_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name=Workable.TypeEnum.JOBS.value,
    sub_dag_func=class_sub_dag,
    _class=Workable.TypeEnum.JOBS
)

candidates_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name=Workable.TypeEnum.CANDIDATES.value,
    sub_dag_func=class_sub_dag,
    _class=Workable.TypeEnum.CANDIDATES
)

fact_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='fact',
    sub_dag_func=fact_load_sub_dag
)

# flow
fact_sub_dag.set_upstream([members_sub_dag, jobs_sub_dag, candidates_sub_dag])

# TODO: add unit tests
