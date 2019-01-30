import json
from datetime import datetime

from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.kill_queue.killqueue import KillQueue

env.set_airflow_var_to_local_env('KILLQUEUE')
logger = QuintoAndarLogger('kill_queue')

MAIN_DAG_NAME = 'kill-queue-etl'
MAIN_START_DATE = datetime(2019, 1, 27)
MAIN_SCHEDULE_INTERVAL = '0 1 1/1 * *'

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

params = env.get_airflow_env_var('KILLQUEUE_PARAMS')
kill_queue = KillQueue(s3_bucket)


def extract_data_and_move_to_raw(**kwargs):
    table = kwargs.get('table')
    kill_queue.extract_data_and_move_to_raw(table)


def move_data_from_raw_to_clean(**kwargs):
    table = kwargs.get('table')
    kill_queue.move_data_from_raw_to_clean(table)


dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=env.convert_to_utc_schedule(MAIN_SCHEDULE_INTERVAL),
    max_active_runs=1,
    catchup=False
)

# operators
tables = json.loads(params).get("tables")

extract_data_ops = []
move_data_to_clean_ops = []
for table in tables:
    extract_data_op = BaseDAG.build_python_operator(
        dag=dag,
        task_id='extract-data-{}'.format(table),
        python_callable=extract_data_and_move_to_raw,
        provide_context=True,
        op_kwargs={'table': table}
    )
    # extract_data_ops.append(extract_data_and_move_to_raw)

    move_data_to_clean_op = BaseDAG.build_python_operator(
        dag=dag,
        task_id='move-data-to-clean-{}'.format(table),
        python_callable=move_data_from_raw_to_clean,
        provide_context=True,
        op_kwargs={'table': table}
    )
    move_data_to_clean_op.set_upstream(extract_data_op)
    move_data_to_clean_ops.append(move_data_to_clean_op)
