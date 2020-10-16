from airflow import DAG
from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env

from bietlejuice.jobs.etl.zendesk import ZendeskTableEnum, ZendeskFactory

MAIN_DAG_ID = 'bi-zendesk-fact-tickets-reprocessing'
MAIN_START_DATE = datetime(2020, 8, 21, 0, 0, 0)
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


BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='fact_tickets',
    sub_dag_func=sub_dag_dw,
    class_=ZendeskTableEnum.FACT_TICKETS
)
