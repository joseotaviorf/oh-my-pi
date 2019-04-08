from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import ShortCircuitOperator

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.asterisk import AsteriskFactory, AsteriskTableEnum

# env vars
env.set_airflow_var_to_local_env('BI_DW', 'ASTERISK')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_ID = 'bi-asterisk-load'
MAIN_START_DATE = datetime(2016, 7, 26)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')


# functions
def data_existence_check(class_, bucket_type, **kwargs):
    asterisk = AsteriskFactory.factory(
        entity=class_,
        s3_bucket=s3_bucket,
        execution_date=kwargs['execution_date']
    )

    return asterisk.data_existence_check(bucket_type)


def upsert_partition(class_, bucket_type, **kwargs):
    asterisk = AsteriskFactory.factory(
        entity=class_,
        s3_bucket=s3_bucket,
        execution_date=kwargs['execution_date']
    )

    asterisk._upsert_partition(
        class_=class_,
        bucket_type=bucket_type

    )


def exec_factory_method(class_, method, **kwargs):
    asterisk = AsteriskFactory.factory(
        entity=class_,
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


def raw_sub_dag(sub_dag_name, storage_format, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_data_task = BaseDAG.build_python_operator(
        task_id='extract_and_load_data',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'extract_and_load_data'
        }
    )

    data_existence_check_task = ShortCircuitOperator(
        task_id='raw_data_existence_check',
        python_callable=data_existence_check,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'bucket_type': 'raw'
        }
    )
    extract_and_load_data_task >> data_existence_check_task

    if (storage_format == 'partitioned'):
        upsert_raw_partition_task = upsert_partitioned(sub_dag_name, local_dag, 'raw', **kwargs)
        data_existence_check_task >> upsert_raw_partition_task

    return local_dag


def clean_sub_dag(sub_dag_name, storage_format, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    move_to_clean_task = BaseDAG.build_python_operator(
        task_id='move_to_clean',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'move_to_clean'
        }
    )

    if (storage_format == 'partitioned'):
        upsert_clean_partition_task = upsert_partitioned(sub_dag_name, local_dag, 'clean', **kwargs)
        move_to_clean_task >> upsert_clean_partition_task

    return local_dag


def upsert_partitioned(sub_dag_name, local_dag, bucket_type, **kwargs):
    upsert_partition_task = BaseDAG.build_python_operator(
        task_id='upsert_{}_partition'.format(sub_dag_name),
        python_callable=upsert_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'bucket_type': bucket_type
        }
    )

    return upsert_partition_task


def upsert_single_table_partitioned(table_name, local_dag, bucket_type, **kwargs):
    upsert_single_table_partition_task = BaseDAG.build_python_operator(
        task_id='upsert_{}_partition'.format(table_name),
        python_callable=upsert_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'bucket_type': bucket_type
        }
    )

    return upsert_single_table_partition_task


# operators
cdr_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='cdr_raw',
    storage_format='partitioned',
    sub_dag_func=raw_sub_dag,
    class_=AsteriskTableEnum.CDR
)

cdr_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='cdr_clean',
    storage_format='partitioned',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.CDR
)

logs_full_raw_partition_task = upsert_partitioned(
    sub_dag_name='logs_full_raw',
    local_dag=main_dag,
    bucket_type='raw',
    class_=AsteriskTableEnum.LOGS_FULL
)

calls_details_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='calls_details_clean',
    storage_format='partitioned',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.CALLS_DETAILS
)

events_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='events_clean',
    storage_format='partitioned',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.EVENTS
)

events_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='events_clean',
    storage_format='partitioned',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.EVENTS
)

cxpanel_queues_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='cxpanel_queues_raw',
    storage_format='full',
    sub_dag_func=raw_sub_dag,
    class_=AsteriskTableEnum.CXPANEL_QUEUES
)

cxpanel_queues_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='cxpanel_queues_clean',
    storage_format='full',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.CXPANEL_QUEUES
)

cxpanel_users_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='cxpanel_users_raw',
    storage_format='full',
    sub_dag_func=raw_sub_dag,
    class_=AsteriskTableEnum.CXPANEL_USERS
)

cxpanel_users_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='cxpanel_users_clean',
    storage_format='full',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.CXPANEL_USERS
)

devices_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='devices_raw',
    storage_format='full',
    sub_dag_func=raw_sub_dag,
    class_=AsteriskTableEnum.DEVICES
)

devices_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='devices_clean',
    storage_format='full',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.DEVICES
)

ivr_details_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='ivr_details_raw',
    storage_format='full',
    sub_dag_func=raw_sub_dag,
    class_=AsteriskTableEnum.IVR_DETAILS
)

ivr_details_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='ivr_details_clean',
    storage_format='full',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.IVR_DETAILS
)

ivr_entries_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='ivr_entries_raw',
    storage_format='full',
    sub_dag_func=raw_sub_dag,
    class_=AsteriskTableEnum.IVR_ENTRIES
)

ivr_entries_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='ivr_entries_clean',
    storage_format='full',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.IVR_ENTRIES
)

queues_config_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='queues_config_raw',
    storage_format='full',
    sub_dag_func=raw_sub_dag,
    class_=AsteriskTableEnum.QUEUES_CONFIG
)

queues_config_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='queues_config_clean',
    storage_format='full',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.QUEUES_CONFIG
)

queues_details_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='queues_details_raw',
    storage_format='full',
    sub_dag_func=raw_sub_dag,
    class_=AsteriskTableEnum.QUEUES_DETAILS
)

queues_details_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='queues_details_clean',
    storage_format='full',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.QUEUES_DETAILS
)

users_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='users_raw',
    storage_format='full',
    sub_dag_func=raw_sub_dag,
    class_=AsteriskTableEnum.USERS
)

users_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='users_clean',
    storage_format='full',
    sub_dag_func=clean_sub_dag,
    class_=AsteriskTableEnum.USERS
)

# flow
logs_full_raw_partition_task.set_downstream([calls_details_clean_sub_dag_task, events_clean_sub_dag_task])
cdr_raw_sub_dag_task >> cdr_clean_sub_dag_task
cxpanel_queues_raw_sub_dag_task >> cxpanel_queues_clean_sub_dag_task
cxpanel_users_raw_sub_dag_task >> cxpanel_users_clean_sub_dag_task
devices_raw_sub_dag_task >> devices_clean_sub_dag_task
ivr_details_raw_sub_dag_task >> ivr_details_clean_sub_dag_task
ivr_entries_raw_sub_dag_task >> ivr_entries_clean_sub_dag_task
queues_config_raw_sub_dag_task >> queues_config_clean_sub_dag_task
queues_details_raw_sub_dag_task >> queues_details_clean_sub_dag_task
users_raw_sub_dag_task >> users_clean_sub_dag_task

# TODO: add unit tests
