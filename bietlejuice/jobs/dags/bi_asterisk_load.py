from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.operators.python_operator import ShortCircuitOperator

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.asterisk import AsteriskFactory, AsteriskTableEnum

# env vars
env.set_airflow_var_to_local_env('BI_DW', 'ASTERISK')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_ID = 'bi-asterisk-load'
MAIN_START_DATE = datetime(2016, 7, 26)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')


# functions
def data_existence_check(_class, bucket_type, **kwargs):
    asterisk = AsteriskFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        execution_date=kwargs['execution_date']
    )

    return asterisk.data_existence_check(bucket_type)


def upsert_partition(_class, bucket_type, **kwargs):
    asterisk = AsteriskFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        execution_date=kwargs['execution_date']
    )

    asterisk._upsert_partition(
        _class=_class,
        bucket_type=bucket_type

    )


def exec_factory_method(_class, method, **kwargs):
    asterisk = AsteriskFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        execution_date=kwargs['execution_date']
    )

    getattr(asterisk, method)()


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
    max_active_runs=1
)


def partitioned_class_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_data_task = BaseDAG.get_quintoandar_python_operator(
        task_id='extract_and_load_data',
        func_command=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'extract_and_load_data'
        }
    )

    data_existence_check_task = ShortCircuitOperator(
        task_id='raw_data_existence_check',
        python_callable=data_existence_check,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'bucket_type': 'raw'
        }
    )

    upsert_raw_partition_task = BaseDAG.get_quintoandar_python_operator(
        task_id='upsert_raw_partition',
        func_command=upsert_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'bucket_type': 'raw'
        }
    )

    move_to_clean_task = BaseDAG.get_quintoandar_python_operator(
        task_id='move_to_clean',
        func_command=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'move_to_clean'
        }
    )

    upsert_clean_partition_task = BaseDAG.get_quintoandar_python_operator(
        task_id='upsert_clean_partition',
        func_command=upsert_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'bucket_type': 'clean'
        }
    )

    airflow_helpers.chain(
        extract_and_load_data_task,
        data_existence_check_task,
        upsert_raw_partition_task,
        move_to_clean_task,
        upsert_clean_partition_task
    )

    return local_dag


def full_class_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_data_task = BaseDAG.get_quintoandar_python_operator(
        task_id='extract_and_load_data',
        func_command=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'extract_and_load_data'
        }
    )

    data_existence_check_task = ShortCircuitOperator(
        task_id='raw_data_existence_check',
        python_callable=data_existence_check,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'bucket_type': 'raw'
        }
    )

    move_to_clean_task = BaseDAG.get_quintoandar_python_operator(
        task_id='move_to_clean',
        func_command=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'move_to_clean'
        }
    )

    airflow_helpers.chain(
        extract_and_load_data_task,
        data_existence_check_task,
        move_to_clean_task
    )

    return local_dag


# operators
cdr_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='cdr',
    sub_dag_func=partitioned_class_sub_dag,
    _class=AsteriskTableEnum.CDR
)

cxpanel_queues_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='cxpanel_queues',
    sub_dag_func=full_class_sub_dag,
    _class=AsteriskTableEnum.CXPANEL_QUEUES
)

cxpanel_users_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='cxpanel_users',
    sub_dag_func=full_class_sub_dag,
    _class=AsteriskTableEnum.CXPANEL_USERS
)

devices_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='devices',
    sub_dag_func=full_class_sub_dag,
    _class=AsteriskTableEnum.DEVICES
)

ivr_details_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='ivr_details',
    sub_dag_func=full_class_sub_dag,
    _class=AsteriskTableEnum.IVR_DETAILS
)

ivr_entries_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='ivr_entries',
    sub_dag_func=full_class_sub_dag,
    _class=AsteriskTableEnum.IVR_ENTRIES
)

queues_config_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='queues_config',
    sub_dag_func=full_class_sub_dag,
    _class=AsteriskTableEnum.QUEUES_CONFIG
)

queues_details_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='queues_details',
    sub_dag_func=full_class_sub_dag,
    _class=AsteriskTableEnum.QUEUES_DETAILS
)

users_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='users',
    sub_dag_func=full_class_sub_dag,
    _class=AsteriskTableEnum.USERS
)

# flow

# TODO: add unit tests
