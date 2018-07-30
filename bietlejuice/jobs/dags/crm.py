from datetime import datetime

from airflow.models import DAG

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.crm.tasks import CRMTasksFactory

# env vars
env.set_airflow_var_to_local_env('BI_DW')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
mongo_client_uri = env.get_airflow_env_var('MONGODB_CRM_URI')

MAIN_DAG_NAME = 'bi-crm'
MAIN_START_DATE = datetime(2015, 1, 1)
MAIN_SCHEDULE_INTERVAL = '0 1 * * *'


# functions
def upsert_partition(_class, bucket_type, **kwargs):
    crm_tasks = CRMTasksFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_tasks._upsert_partition(bucket_type)


def extract_and_load_data(_class, **kwargs):
    crm_tasks = CRMTasksFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_tasks.extract_and_load_data()


def move_to_clean(_class, **kwargs):
    crm_tasks = CRMTasksFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_tasks.move_to_clean()


def load_dim(_class, **kwargs):
    crm_tasks = CRMTasksFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_tasks._load_dim()


def load_fact(_class, **kwargs):
    crm_tasks = CRMTasksFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_tasks._load_fact()


# dags
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=env.convert_to_utc_schedule(MAIN_SCHEDULE_INTERVAL),
    max_active_runs=1
)


def class_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_task = BaseDAG.get_quintoandar_python_operator(
        task_id='extract_and_load',
        func_command=extract_and_load_data,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class']
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
        func_command=move_to_clean,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'bucket_type': 'clean'
        }
    )

    upsert_clean_partition_task = BaseDAG.get_quintoandar_python_operator(
        task_id='upsert_clean_partition',
        func_command=upsert_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class']
        }
    )

    load_dim_task = BaseDAG.get_quintoandar_python_operator(
        task_id='load_dim',
        func_command=load_dim,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class']
        }
    )

    load_fact_task = BaseDAG.get_quintoandar_python_operator(
        task_id='load_fact',
        func_command=load_fact,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class']
        }
    )

    extract_and_load_task >> upsert_raw_partition_task >> move_to_clean_task >> upsert_clean_partition_task
    upsert_clean_partition_task.set_downstream([load_dim_task, load_fact_task])

    return local_dag


# operators
tasks_credit_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_credit',
    sub_dag_func=class_sub_dag,
    _class='credit'
)

# TODO: add unit tests
