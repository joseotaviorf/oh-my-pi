import os
import boto3
from datetime import datetime

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
MAIN_START_DATE = datetime(2020, 4, 19)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 9 * * *')

METRICS_SCHEMA = 'metrics'
DATA_METRICS_BUCKET_NAME = '5a-data-metrics'

logger = QuintoAndarLogger(MAIN_DAG_ID)


# functions
@logger
def read_data_metrics_repo_and_return_sqls():
    logger.info('m=read_data_metrics_repo_and_return_sqls, msg=listing s3 bucket contents and downloading SQL files')
    s3_client = boto3.client('s3', aws_access_key_id=data_acc_aws_access_key_id, aws_secret_access_key=data_acc_aws_secret_access_key)
    objects = s3_client.list_objects_v2(Bucket=DATA_METRICS_BUCKET_NAME)['Contents']
    sqls = []
    for object in [x for x in objects if x['Key'].endswith('.sql')]:
        file_stem = os.path.split(object['Key'])[1].replace('.sql', '')
        object_body = s3_client.get_object(Bucket=DATA_METRICS_BUCKET_NAME, Key=object['Key'])['Body'].read().decode('utf-8')
        sqls.append({'table_name': file_stem, 'sql': object_body})
    return sqls


@logger
def create_metric_from_dw(table_name, query, **kwargs):
    drop_table_sql = 'drop table if exists {}.{}'.format(METRICS_SCHEMA, table_name)
    create_table_sql = 'create table {}.{} as ({})'.format(METRICS_SCHEMA, table_name, query.replace(';', ''))
    transaction_sql = 'begin;\n {};\n {};\n commit;'.format(drop_table_sql, create_table_sql)

    logger.info('m=create_metric_from_dw, table_name={}, sql={}, msg=Dropping and creating new table'.format(table_name, transaction_sql))
    BaseETL.execute_command(
        command=transaction_sql,
        db_enum=EnumDB.BI_DW,
        encoding='utf-8',
        commit=True
    )


def create_task(dag, python_callable, db, table_name, query):
    task = BaseDAG.build_python_operator(
        dag=dag,
        task_id='{}_{}'.format(db, table_name),
        provide_context=True,
        pool='redshift_bi_metrics_pool',
        python_callable=python_callable,
        op_kwargs={'table_name': table_name, 'query': query}
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

sqls = read_data_metrics_repo_and_return_sqls()

# create metrics tasks
for sql in sqls:
    create_task(
        dag=main_dag,
        python_callable=create_metric_from_dw,
        db='dw',
        table_name=sql['table_name'],
        query=sql['sql'],
    )
