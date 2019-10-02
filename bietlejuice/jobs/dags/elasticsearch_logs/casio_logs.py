import os
from airflow.models import DAG
from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.elasticsearch_logs import ml_logs_to_s3
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.elasticsearch import CasioLogsFetcher
from qa_python_utils.aws.athena import AthenaClient

athena = AthenaClient('5a-datalake')

MAIN_DAG_NAME = 'casio-logs'
MAIN_START_DATE = datetime(2019, 9, 11)
MAIN_SCHEDULE_INTERVAL = '0 3 * * *'  # 3am UTC every day

env.set_airflow_var_to_local_env('ES_LOGS__HOSTNAME')

config = {
    'es_extractor': CasioLogsFetcher(
        es_logs__hostname=os.getenv('ES_LOGS__HOSTNAME'), model_logger_name='CasioModel'
    ),
    'app_name': 'casio',
    'model_name': 'CasioModel',
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
    op_kwargs={"database": "ml_logs", "table_name": "casio"}
)

dump_logs_to_datalake_raw_op >> update_table
