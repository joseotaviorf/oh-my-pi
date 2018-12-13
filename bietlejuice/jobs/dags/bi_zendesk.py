from airflow import DAG
from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env

MAIN_DAG_NAME = 'bi-zendesk-flow'
MAIN_START_DATE = datetime(2018, 12, 10, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('30 */6 * * *')

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

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
    catchup=True,
    max_active_runs=1
)

# def clean_sub_dag(sub_dag_name, class_):
#     sub_dag = ZendeskFactory.factory(
#         class_=class_,
#         bucket=s3_bucket,
#         sub_dag_name=sub_dag_name,
#         dag_name=MAIN_DAG_NAME,
#         schedule_interval=MAIN_SCHEDULE_INTERVAL,
#         start_date=MAIN_START_DATE
#     )
