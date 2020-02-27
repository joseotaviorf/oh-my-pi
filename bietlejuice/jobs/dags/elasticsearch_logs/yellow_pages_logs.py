import os
from airflow.models import DAG
from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.elasticsearch_logs import ml_logs_to_s3
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.elasticsearch import YellowPagesLogsFetcher
from qa_python_utils.aws.athena import AthenaClient

env.set_airflow_var_to_local_env('ES_LOGS__HOSTNAME', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
athena = AthenaClient(bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)

MAIN_DAG_NAME = 'yellow-pages-logs'
MAIN_START_DATE = datetime(2019, 11, 20)
MAIN_SCHEDULE_INTERVAL = '0 3 * * *'  # 3am UTC every day

config = {
    'es_extractor': YellowPagesLogsFetcher(
        es_logs__hostname=os.getenv('ES_LOGS__HOSTNAME'), logger_name='YellowPages'
    ),
    'app_name': 'yellow-pages',
    'model_name': 'YellowPages',
}

dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1
)

dump_logs_to_datalake_raw_op = BaseDAG.build_python_operator(
    dag=dag,
    task_id='dump_logs_to_datalake_raw',
    provide_context=True,
    python_callable=ml_logs_to_s3,
    op_kwargs=config
)

update_table = BaseDAG.build_python_operator(
    dag=dag,
    task_id='repair_table',
    python_callable=athena.msck_repair_table,
    op_kwargs={"database": "ml_logs", "table_name": "yellow_pages"}
)

dump_logs_to_datalake_raw_op >> update_table
