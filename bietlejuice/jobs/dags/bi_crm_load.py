from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.operators.python_operator import ShortCircuitOperator

import bietlejuice.jobs.new_etl.powerbi as powerbi
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.crm.tasks import CRMTasks, CRMTasksFactory, CRMTasksTableEnum

# env vars
env.set_airflow_var_to_local_env('BI_DW')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
mongo_client_uri = env.get_airflow_env_var('MONGODB_CRM_URI')

PWBI_AUTH = env.get_airflow_env_var('PWBI_AUTH')
PWBI_SCHEMA = env.get_airflow_env_var('PWBI_SCHEMA')
MAIN_DAG_ID = 'bi-crm-load'
MAIN_START_DATE = datetime(2018, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')


# functions
def data_existence_check(bucket_type, **kwargs):
    crm_tasks = CRMTasks(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    return crm_tasks.data_existence_check(bucket_type)


def upsert_partition(bucket_type, method, **kwargs):
    crm_tasks = CRMTasks(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    getattr(crm_tasks, method)(bucket_type)


def extract_and_load_data(**kwargs):
    crm_tasks = CRMTasks(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_tasks.extract_and_load_data()


def exec_crm_method(method, **kwargs):
    crm_tasks = CRMTasks(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    getattr(crm_tasks, method)()


def exec_factory_method(_class, method, **kwargs):
    crm_tasks = CRMTasksFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    getattr(crm_tasks, method)()


def refresh_powerbi(**kwargs):
    powerbi_client = powerbi.PowerBIClient(PWBI_AUTH,
                                           PWBI_SCHEMA,
                                           kwargs['workspace_name'],
                                           kwargs['dataset_name'])
    powerbi_client.trigger_refresh()


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

    move_dim_to_staging_task = BaseDAG.build_quintoandar_python_operator(
        task_id='move_dim_to_staging',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'move_dim_to_staging'
        }
    )

    move_fact_to_staging_task = BaseDAG.build_quintoandar_python_operator(
        task_id='move_fact_to_staging',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'move_fact_to_staging'
        }
    )

    append_dim_to_dw_task = BaseDAG.build_quintoandar_python_operator(
        task_id='append_dim_to_dw',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'append_dim_to_dw'
        }
    )

    append_fact_to_dw_task = BaseDAG.build_quintoandar_python_operator(
        task_id='append_fact_to_dw',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'append_fact_to_dw'
        }
    )

    delete_staging_fact_entries_task = BaseDAG.build_quintoandar_python_operator(
        task_id='delete_staging_fact_entries',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'delete_staging_fact_entries'
        }
    )

    delete_staging_dim_entries_task = BaseDAG.build_quintoandar_python_operator(
        task_id='delete_staging_dim_entries',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'delete_staging_dim_entries'
        }
    )

    airflow_helpers.chain(
        move_dim_to_staging_task,
        append_dim_to_dw_task,
        delete_staging_dim_entries_task
    )

    airflow_helpers.chain(
        move_fact_to_staging_task,
        append_fact_to_dw_task,
        delete_staging_fact_entries_task
    )

    return local_dag


def clean_tasks_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    move_tasks_to_clean_task = BaseDAG.build_quintoandar_python_operator(
        task_id='move_tasks_to_clean',
        python_callable=exec_crm_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'method': '_move_tasks_to_clean'
        }
    )

    upsert_tasks_clean_partition_task = BaseDAG.build_quintoandar_python_operator(
        task_id='upsert_tasks_clean_partition',
        python_callable=upsert_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'clean',
            'method': '_upsert_tasks_partition'
        }
    )

    move_tasks_to_clean_task >> upsert_tasks_clean_partition_task

    return local_dag


def clean_task_resolution_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    move_tasks_resolution_to_clean_task = BaseDAG.build_quintoandar_python_operator(
        task_id='move_tasks_resolution_to_clean',
        python_callable=exec_crm_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'method': '_move_tasks_resolution_to_clean'
        }
    )

    upsert_tasks_resolution_clean_partition_task = BaseDAG.build_quintoandar_python_operator(
        task_id='upsert_tasks_resolution_clean_partition',
        python_callable=upsert_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'clean',
            'method': '_upsert_tasks_resolution_partition'
        }
    )

    move_tasks_resolution_to_clean_task >> upsert_tasks_resolution_clean_partition_task

    return local_dag


# operators
extract_and_load_task = BaseDAG.build_quintoandar_python_operator(
    task_id='extract_and_load',
    python_callable=extract_and_load_data,
    dag=main_dag,
    provide_context=True
)

data_existence_check_task = ShortCircuitOperator(
    task_id='data_existence_check',
    python_callable=data_existence_check,
    dag=main_dag,
    provide_context=True,
    op_kwargs={
        'bucket_type': 'raw'
    }
)

upsert_raw_partition_task = BaseDAG.build_quintoandar_python_operator(
    task_id='upsert_raw_partition',
    python_callable=upsert_partition,
    dag=main_dag,
    provide_context=True,
    op_kwargs={
        'bucket_type': 'raw',
        'method': '_upsert_tasks_partition'
    }
)

clean_tasks_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='create_clean_tasks_table',
    sub_dag_func=clean_tasks_sub_dag,
)

clean_tasks_resolution_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='create_clean_tasks_resolution_table',
    sub_dag_func=clean_task_resolution_sub_dag,
)

tasks_credit_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_credit',
    sub_dag_func=class_sub_dag,
    _class=CRMTasksTableEnum.CREDIT
)

tasks_visit_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_visit',
    sub_dag_func=class_sub_dag,
    _class=CRMTasksTableEnum.VISIT,
    has_bridge=True
)

tasks_closing_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_closing',
    sub_dag_func=class_sub_dag,
    _class=CRMTasksTableEnum.CLOSING
)

tasks_onboarding_tenant_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_onboarding_tenant',
    sub_dag_func=class_sub_dag,
    _class=CRMTasksTableEnum.ONBOARDING_TENANT
)

tasks_payment_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_payment',
    sub_dag_func=class_sub_dag,
    _class=CRMTasksTableEnum.PAYMENT
)

refresh_credit_task = BaseDAG.build_quintoandar_python_operator(
    dag=main_dag,
    task_id='Refresh_PowerBI_Credit_Task',
    python_callable=refresh_powerbi,
    op_kwargs={'workspace_name': 'Scalability', 'dataset_name': 'CRM credit tasks'}
)

refresh_visit_task = BaseDAG.build_quintoandar_python_operator(
    dag=main_dag,
    task_id='Refresh_PowerBI_Visit_Task',
    python_callable=refresh_powerbi,
    op_kwargs={'workspace_name': 'Scalability', 'dataset_name': 'CRM visits tasks'}
)

# flow
airflow_helpers.chain(
    extract_and_load_task,
    data_existence_check_task,
    upsert_raw_partition_task,
    clean_tasks_sub_dag_task,
    clean_tasks_resolution_sub_dag_task
)

clean_tasks_resolution_sub_dag_task.set_downstream(
    [
        tasks_credit_sub_dag,
        tasks_visit_sub_dag,
        tasks_closing_sub_dag,
        tasks_onboarding_tenant_sub_dag,
        tasks_payment_sub_dag
    ]
)
tasks_credit_sub_dag >> refresh_credit_task
tasks_visit_sub_dag >> refresh_visit_task

# TODO: add unit tests
