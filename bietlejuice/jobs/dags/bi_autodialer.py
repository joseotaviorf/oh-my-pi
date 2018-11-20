from datetime import datetime
from os import listdir

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
# env vars
from bietlejuice.jobs.new_etl.autodialer import AUTODIALER_DATALAKE_QUERIES_DIR
from bietlejuice.jobs.new_etl.autodialer.autodialer import AutodialerETL
from qa_python_utils import QuintoAndarLogger

env.set_airflow_var_to_local_env('BI_DW')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_NAME = 'bi-autodialer'
MAIN_START_DATE = datetime(2018, 11, 15, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')

logger = QuintoAndarLogger(MAIN_DAG_NAME)

# dags
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
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


@logger
def get_files_list(document_type):
    path = '{}/{}'.format(AUTODIALER_DATALAKE_QUERIES_DIR, document_type)
    return path, listdir(path)


def clean_sub_dag(sub_dag_name):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    _, dir_files = get_files_list('task_references')
    if len(dir_files) > 0:
        for _file in dir_files:
            BaseDAG.build_python_operator(
                dag=local_dag,
                task_id='{}_to_clean'.format(_file.split(".")[0]),
                python_callable=clean_dag,
                provide_context=True,
                op_kwargs={
                    'document_type': 'task_references'
                }
            )

    return local_dag


@logger
def task_references_raw_dag(**kwargs):
    autodialer = AutodialerETL(
        bucket_name=s3_bucket,
        execution_date=kwargs['execution_date']
    )
    autodialer.move_data_to_raw('task_references')


@logger
def clean_dag(document_type, **kwargs):
    autodialer = AutodialerETL(
        bucket_name=s3_bucket,
        execution_date=kwargs['execution_date']
    )
    autodialer.move_data_to_clean(document_type)


task_references_raw = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='task_references_raw',
    python_callable=task_references_raw_dag,
    provide_context=True,
)

task_references_clean = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=clean_sub_dag,
    sub_dag_name='task_references_clean'
)

task_references_raw >> task_references_clean
