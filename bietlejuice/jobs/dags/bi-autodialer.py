from airflow.models import DAG
from datetime import datetime
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
# env vars
from bietlejuice.jobs.new_etl.autodialer.autodialer import Autodialer_ETL

env.set_airflow_var_to_local_env('BI_DW')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_ID = 'bi-autodialer'
MAIN_START_DATE = datetime(2018, 8, 22)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 9 * * *')

logger = QuintoAndarLogger(MAIN_DAG_ID)

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


def task_references_raw_dag(**kwargs):
    autodialer = Autodialer_ETL(
        bucket_name=s3_bucket,
        execution_date=kwargs['execution_date']
    )
    autodialer.move_data_to_raw('task_references')


def task_references_clean_dag(**kwargs):
    autodialer = Autodialer_ETL(
        bucket_name=s3_bucket,
        execution_date=kwargs['execution_date']
    )
    autodialer.move_data_to_clean('task_references')
