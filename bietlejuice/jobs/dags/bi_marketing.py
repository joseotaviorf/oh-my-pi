from datetime import datetime

from airflow.models import DAG

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.marketing.to_clean.googleads_clean_subdag import GoogleAdsCleanSubDag
from bietlejuice.jobs.dags.marketing.to_raw.googleads_raw_subdag import GoogleAdsStitchSubDag
from bietlejuice.jobs.dags.marketing.to_raw.facebook_ads_raw_subdag import FacebookAdsSubDag
from bietlejuice.jobs.dags.util import environment as env

MAIN_DAG_NAME = 'bi-marketing'
MAIN_START_DATE = datetime(2018, 01, 01, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')

FACEBOOK_ADS_ACCOUNTS = ['demand_acqui2sition', 'social', 'demand_retargeting', 'supply_affiliates', 'supply_landlords']
GOOGLE_ADS_ACCOUNTS = [
    'quintoandar_belo_horizonte',
    'quintoandar_brasilia',
    'quintoandar_display',
    'quintoandar_dra',
    'quintoandar_dsa',
    'quintoandar_goiania',
    'quintoandar_institucional',
    'quintoandar_other_cities',
    'quintoandar_rio_de_janeiro',
    'quintoandar_sao_paulo',
    'quintoandar_universal_app_campaigns',
    'quintoandar_supply_belo_horizonte',
    'quintoandar_supply_brasilia',
    'quintoandar_supply_goiania',
    'quintoandar_supply_jundiai',
    'quintoandar_supply_niteroi',
    'quintoandar_supply_other_cities',
    'quintoandar_supply_rio_de_janeiro',
    'quintoandar_supply_sao_paulo'
]

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
    catchup=True,
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


def googleads_raw_sub_dag(sub_dag_name):
    sub_dag = GoogleAdsStitchSubDag(
        s3_bucket,
        sub_dag_name,
        MAIN_DAG_NAME,
        MAIN_SCHEDULE_INTERVAL,
        MAIN_START_DATE,
        STITCH_DATABASE
    )

    return sub_dag.build_googleads_raw_tasks()


def googleads_clean_sub_dag(sub_dag_name):
    sub_dag = GoogleAdsCleanSubDag(
        s3_bucket,
        sub_dag_name,
        MAIN_DAG_NAME,
        MAIN_SCHEDULE_INTERVAL,
        MAIN_START_DATE,
        GOOGLE_ADS_ACCOUNTS
    )

    return sub_dag.build_googleads_clean_tasks()


facebook_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=facebook_sub_dag,
    sub_dag_name="stitch-facebookads-to-raw"
)

googleads_raw_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=googleads_raw_sub_dag,
    sub_dag_name='stitch-googleads-to-raw'
)

googleads_clean_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=googleads_clean_sub_dag,
    sub_dag_name='google-ads-raw-to-clean'
)
