import os
import boto3
from datetime import datetime
from pathlib import Path
import shutil

from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env

# env vars
env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')

MAIN_DAG_ID = 'bi-metrics'
MAIN_START_DATE = datetime(2020, 04, 19)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 9 * * *')

METRICS_SCHEMA = 'metrics'
DATA_METRICS_REPO_NAME = 'data-metrics'
DATA_METRICS_BUCKET_NAME = '5a-data-metrics'
CLONE_TO_FOLDER = '/tmp'
REPO_FOLDER = '{}/{}'.format(CLONE_TO_FOLDER, DATA_METRICS_REPO_NAME)

logger = QuintoAndarLogger(MAIN_DAG_ID)


# functions
@logger
def copy_data_metrics_repo_sqls(**kwargs):
    logger.info('m=copy_data_metrics_repo_sqls, msg=listing s3 bucket contents and downloading SQL files')
    s3_client = boto3.client('s3', aws_access_key_id=data_acc_aws_access_key_id, aws_secret_access_key=data_acc_aws_secret_access_key)
    objects = s3_client.list_objects_v2(Bucket=DATA_METRICS_BUCKET_NAME)['Contents']
    if os.path.isdir(REPO_FOLDER):
        # cleanup folder to remove old files
        shutil.rmtree(REPO_FOLDER)
    Path(REPO_FOLDER).mkdir(parents=True)
    for object in [x for x in objects if x['Key'].endswith('.sql')]:
        file_name = os.path.split(object['Key'])[1]
        # download sql files
        s3_client.download_file(DATA_METRICS_BUCKET_NAME, object['Key'], '{}/{}'.format(REPO_FOLDER, file_name))


@logger
def create_metric_from_dw(table_name, file_path, **kwargs):
    query = BaseETL.get_query_from_file_name(file_path)

    logger.info('m=create_metric_from_dw, table_name={}, msg=Dropping table'.format(table_name))
    BaseETL.execute_command(
        command='drop table if exists {}.{}'.format(METRICS_SCHEMA, table_name),
        db_enum=EnumDB.BI_DW,
        encoding='utf-8',
        commit=False
    )

    logger.info('m=create_metric_from_dw, table_name={}, msg=Creating table'.format(table_name))
    BaseETL.execute_command(
        command='create table {}.{} as ({})'.format(METRICS_SCHEMA, table_name, query.replace(';', '')),
        db_enum=EnumDB.BI_DW,
        encoding='utf-8',
        commit=True
    )


def create_task(dag, python_callable, db, file_path, table_name):
    task = BaseDAG.build_python_operator(
        dag=dag,
        task_id='{}_{}'.format(db, table_name),
        provide_context=True,
        python_callable=python_callable,
        op_kwargs={'table_name': table_name, 'file_path': file_path}
    )
    return task


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

copy_repo_sqls_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='copy_data_metrics_repo_sqls',
    provide_context=True,
    python_callable=copy_data_metrics_repo_sqls
)

# create metrics tasks
tasks = []
for path in [p for p in Path(REPO_FOLDER).rglob('*.sql')]:
    task = create_task(
        dag=main_dag,
        python_callable=create_metric_from_dw,
        db='dw',
        file_path=path.as_posix(),
        table_name=path.stem,
    )
    tasks.append(task)

copy_repo_sqls_task.set_downstream(tasks)
