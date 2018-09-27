from datetime import datetime

from airflow.models import DAG

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.market_cost.facebook_ads_subdag import FacebookAdsSubDag
from bietlejuice.jobs.dags.util import environment as env

MAIN_DAG_NAME = 'bi-stitch-raw-transfer'
MAIN_START_DATE = datetime(2018, 1, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')

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
    catchup=False,
    max_active_runs=1
)


def facebook_sub_dag(sub_dag_name):
    sub_dag = FacebookAdsSubDag(
        s3_bucket,
        sub_dag_name,
        MAIN_DAG_NAME,
        MAIN_SCHEDULE_INTERVAL,
        MAIN_START_DATE
    )

    return sub_dag.build_facebook_tasks()


facebook_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=facebook_sub_dag,
    sub_dag_name="FacebookAds"
)
