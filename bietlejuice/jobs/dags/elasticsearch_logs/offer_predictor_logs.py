import os
from airflow.models import DAG

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.elasticsearch_logs import skynet_logs_to_s3

MAIN_DAG_NAME = 'offer-predictor-logs'
MAIN_START_DATE = '2019-02-26'
MAIN_SCHEDULE_INTERVAL = '0 3 * * *'  # 3am UTC every day

env.set_airflow_var_to_local_env('ES_LOGS__HOSTNAME')

config = {
    'ES_LOGS__HOSTNAME': os.getenv('ES_LOGS__HOSTNAME'),
    'MODEL_NAME': 'OfferPredictor',
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
    max_active_runs=1,
    catchup=False
)

dump_logs_to_datalake_raw_op = BaseDAG.build_python_operator(
    dag=dag,
    task_id='dump_logs_to_datalake_raw',
    provide_context=True,
    python_callable=skynet_logs_to_s3,
    op_kwargs=config
)
