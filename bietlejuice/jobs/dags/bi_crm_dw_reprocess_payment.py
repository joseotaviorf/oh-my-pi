from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.crm.tasks import CRMTasksFactory, CRMTasksTableEnum

# env vars
env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
S3_BUCKET = env.get_airflow_env_var('bi-datalake-s3-bucket')
MONGO_CLIENT_URI = env.get_airflow_env_var('MONGODB_CRM_URI')

MAIN_DAG_ID = 'bi-crm-dw-reprocess-payment'
MAIN_START_DATE = datetime(2020, 5, 1)
MAIN_SCHEDULE_INTERVAL = "0 3 * * *"


# functions
def exec_factory_method(class_, method, **kwargs):
    crm_tasks = CRMTasksFactory.factory(
        class_=class_,
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
        execution_date=kwargs['execution_date']
    )

    getattr(crm_tasks, method)()


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


def class_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    move_dim_to_staging_task = BaseDAG.build_python_operator(
        task_id='move_dim_to_staging',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'move_dim_to_staging'
        }
    )

    move_fact_to_staging_task = BaseDAG.build_python_operator(
        task_id='move_fact_to_staging',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'move_fact_to_staging'
        }
    )

    append_dim_to_dw_task = BaseDAG.build_python_operator(
        task_id='append_dim_to_dw',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'append_dim_to_dw'
        }
    )

    append_fact_to_dw_task = BaseDAG.build_python_operator(
        task_id='append_fact_to_dw',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'append_fact_to_dw'
        }
    )

    delete_staging_fact_entries_task = BaseDAG.build_python_operator(
        task_id='delete_staging_fact_entries',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'delete_staging_fact_entries'
        }
    )

    delete_staging_dim_entries_task = BaseDAG.build_python_operator(
        task_id='delete_staging_dim_entries',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
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


tasks_payment_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_payment',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.PAYMENT
)


# TODO: add unit tests
