from datetime import datetime

from airflow.models import DAG

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.marketing.adwords_subdag import AdWordsSubDag
from bietlejuice.jobs.dags.marketing.facebook_ads_subdag import FacebookAdsSubDag
from bietlejuice.jobs.dags.util import environment as env

MAIN_DAG_NAME = 'bi-marketing'
MAIN_START_DATE = datetime(2018, 1, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')
FACEBOOK_ADS_ACCOUNTS = ['demand_acqui2sition', 'social', 'demand_retargeting', 'supply_affiliates', 'supply_landlords']
STITCH_DATABASE = 'stitch'

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


# sub dags
def facebook_sub_dag(sub_dag_name):
    sub_dag = FacebookAdsSubDag(
        s3_bucket,
        sub_dag_name,
        MAIN_DAG_NAME,
        MAIN_SCHEDULE_INTERVAL,
        MAIN_START_DATE,
        STITCH_DATABASE,
        FACEBOOK_ADS_ACCOUNTS
    )

    return sub_dag.build_facebook_tasks()


def adwords_sub_dag(sub_dag_name):
    sub_dag = AdWordsSubDag(
        s3_bucket,
        sub_dag_name,
        MAIN_DAG_NAME,
        MAIN_SCHEDULE_INTERVAL,
        MAIN_START_DATE,
        STITCH_DATABASE
    )

    return sub_dag.build_adwords_tasks()


facebook_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=facebook_sub_dag,
    sub_dag_name="FacebookAds"
)

adwords_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=adwords_sub_dag,
    sub_dag_name='AdWords'
)
