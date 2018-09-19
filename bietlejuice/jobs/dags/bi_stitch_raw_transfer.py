from datetime import datetime

from airflow.models import DAG

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.stitch_transfer_raw import StitchTransferRaw

MAIN_DAG_NAME = 'bi-stitch-raw-transfer'
MAIN_START_DATE = datetime(2018, 1, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')


# functions
def move_files_to_raw(integration, **kwargs):
    transfer = StitchTransferRaw(
        bucket=s3_bucket,
        date=kwargs['execution_date'],
        integration=integration)
    transfer.copy_files()


# dags
dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=False,
    max_active_runs=1
)

BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='move_stitch_faceads_files_to_raw',
    python_callable=move_files_to_raw,
    provide_context=True,
    op_kwargs={
        'integration': 'facebook_ads'
    }
)
