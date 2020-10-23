from airflow import DAG
from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env

from bietlejuice.jobs.etl.zendesk import ZendeskTableEnum, ZendeskFactory
import airflow.utils.helpers as airflow_helpers

MAIN_DAG_ID = 'bi-zendesk-reprocessing'
MAIN_START_DATE = datetime(2019, 4, 8, 0, 0, 0)
MAIN_END_DATE = datetime(2020, 10, 24, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 4 * * *')

env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

# dags
main_dag = DAG(
    dag_id=MAIN_DAG_ID,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    end_date=MAIN_END_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=True,
    max_active_runs=1
)


def exec_factory_method(class_, bucket_type, method, **kwargs):
    zendesk = ZendeskFactory.factory(
        entity=class_,
        s3_bucket=s3_bucket,
        execution_date=kwargs['execution_date']
    )

    op_kwargs = {
        'class_': class_,
        'bucket_type': bucket_type
    }

    getattr(zendesk, method)(**op_kwargs)


def upsert_partitioned(sub_dag_name, local_dag, bucket_type, **kwargs):
    upsert_partition_task = BaseDAG.build_python_operator(
        task_id='upsert_{}_{}_partition'.format(bucket_type, sub_dag_name),
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'bucket_type': bucket_type,
            'method': 'upsert_single_partition'
        }
    )

    return upsert_partition_task


def sub_dag(sub_dag_name, **kwargs):

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
            'bucket_type': 'clean',
            'method': 'move_to_clean'
        }
    )

    upsert_clean_partition_task = upsert_partitioned(sub_dag_name, local_dag, 'clean', **kwargs)

    if kwargs['class_'] == ZendeskTableEnum.CUSTOM_FIELDS:
        move_to_clean_task >> upsert_clean_partition_task
    else:
        # extract and load data by StitchData
        upsert_raw_partition_task = upsert_partitioned(sub_dag_name, local_dag, 'raw', **kwargs)
        airflow_helpers.chain(
            upsert_raw_partition_task,
            move_to_clean_task,
            upsert_clean_partition_task
        )

    return local_dag


def sub_dag_dw(sub_dag_name, **kwargs):

    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    move_to_staging_task = BaseDAG.build_python_operator(
        task_id='move_to_staging',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'bucket_type': 'staging',
            'method': 'move_to_staging'
        }
    )

    move_to_prod_task = BaseDAG.build_python_operator(
        task_id='move_to_prod',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'bucket_type': 'zendesk',
            'method': 'move_to_prod'
        }
    )

    move_to_staging_task >> move_to_prod_task
    return local_dag


tickets_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tickets',
    sub_dag_func=sub_dag,
    class_=ZendeskTableEnum.TICKETS
)

ticket_fields_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='ticket_fields',
    sub_dag_func=sub_dag,
    class_=ZendeskTableEnum.TICKET_FIELDS
)

groups_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='groups',
    sub_dag_func=sub_dag,
    class_=ZendeskTableEnum.GROUPS
)

users_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='users',
    sub_dag_func=sub_dag,
    class_=ZendeskTableEnum.USERS
)

group_memberships_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='group_memberships',
    sub_dag_func=sub_dag,
    class_=ZendeskTableEnum.GROUP_MEMBERSHIPS
)

ticket_metrics_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='ticket_metrics',
    sub_dag_func=sub_dag,
    class_=ZendeskTableEnum.TICKET_METRICS
)

zendesk_custom_fields_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='custom_fields',
    sub_dag_func=sub_dag,
    class_=ZendeskTableEnum.CUSTOM_FIELDS
)

fact_tickets_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='fact_tickets',
    sub_dag_func=sub_dag_dw,
    class_=ZendeskTableEnum.FACT_TICKETS
)

fact_ticket_tags_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='fact_ticket_tags',
    sub_dag_func=sub_dag_dw,
    class_=ZendeskTableEnum.FACT_TICKET_TAGS
)

fact_ticket_contact_types_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='fact_ticket_contact_types',
    sub_dag_func=sub_dag_dw,
    class_=ZendeskTableEnum.FACT_TICKET_CONTACT_TYPES
)

dim_ticket_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='dim_ticket',
    sub_dag_func=sub_dag_dw,
    class_=ZendeskTableEnum.DIM_TICKET
)

dim_zendesk_user_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='dim_zendesk_user',
    sub_dag_func=sub_dag_dw,
    class_=ZendeskTableEnum.DIM_ZENDESK_USER
)

zendesk_custom_fields_sub_dag.set_upstream([tickets_sub_dag, ticket_fields_sub_dag])
dim_ticket_sub_dag.set_upstream([zendesk_custom_fields_sub_dag, groups_sub_dag])
fact_tickets_sub_dag.set_upstream([zendesk_custom_fields_sub_dag, ticket_metrics_sub_dag])
fact_ticket_tags_sub_dag.set_upstream([tickets_sub_dag])
fact_ticket_contact_types_sub_dag.set_upstream([zendesk_custom_fields_sub_dag])
dim_zendesk_user_sub_dag.set_upstream([users_sub_dag])
