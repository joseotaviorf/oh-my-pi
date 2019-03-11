import json
from datetime import datetime

from airflow.contrib.hooks.ssh_hook import SSHHook
from airflow.contrib.operators.sftp_operator import SFTPOperator, SFTPOperation
from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.kenshoo import Kenshoo

# env vars
SFTP_AUTH = json.loads(env.get_airflow_env_var('kenshoo-sftp-authorization'))
S3_BUCKET = env.get_airflow_env_var('bi-datalake-s3-bucket')

# global vars
MAIN_DAG_ID = 'bi-kenshoo'
MAIN_START_DATE = datetime(2019, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 8 * * *')


# functions
def execute_query(query_filename, ds, **kwargs):
    # using dependency injection instead of coupling classes
    athena_client = AthenaClient(S3_BUCKET)
    kenshoo = Kenshoo(
        athena_client=athena_client,
        execution_date=ds
    )
    kenshoo.execute_query_from_file(query_filename)


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

# hooks
ssh_hook = SSHHook(
    remote_host=SFTP_AUTH['host'],
    username=SFTP_AUTH['username'],
    password=SFTP_AUTH['password']
)

# operators
execute_adjust_search_offline_conversions_query_task = PythonOperator(
    task_id='execute_adjust_search_offline_conversions_query',
    python_callable=execute_query,
    provide_context=True,
    op_kwargs={'query_filename': 'adjust_search_offline_conversions.sql'},
    dag=main_dag
)

send_adjust_search_offline_conversions_data_task = SFTPOperator(
    task_id='send_adjust_search_offline_conversions_data',
    ssh_hook=ssh_hook,
    local_filepath='{}-{}.csv'.format(Kenshoo.CSV_PATH_PREFIX, '{{ ds }}'),
    remote_filepath='query_result_{{ ds }}.csv',
    operation=SFTPOperation.PUT,
    dag=main_dag
)

# flow
execute_adjust_search_offline_conversions_query_task >> send_adjust_search_offline_conversions_data_task
