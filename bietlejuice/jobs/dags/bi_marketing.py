from airflow.models import DAG
from datetime import datetime
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.marketing import MarketingSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.marketing.marketing_enum import MarketingEnum

MAIN_DAG_NAME = 'bi-marketing-5'
MAIN_START_DATE = datetime(2018, 10, 22, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')

FACEBOOK_ADS_ACCOUNTS = ['demand_acquisition', 'social', 'demand_retargeting', 'supply_affiliates', 'supply_landlords']
FACEBOOK_ADS_TABLES = ['ads_insights']

GOOGLE_ADS_ACCOUNTS = [
    'quintoandar_belo_horizonte',
    'quintoandar_brasilia',
    'quintoandar_display',
    'quintoandar_dra',
    'quintoandar_dsa',
    'quintoandar_goiania',
    'quintoandar_institucional'
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
GOOGLE_ADS_DATALAKE_TABLES = ['marketing_google_ads_keywords']
GOOGLE_ADS_DW_TABLES = ['dim_google_ads_keyword', 'fact_google_ads_daily_keywords']
GOOGLE_ADS_FACT_TABLE = GOOGLE_ADS_DW_TABLES[1]

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
athena_client = AthenaClient(s3_bucket)

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
    sub_dag = MarketingSubDag(
        clazz=MarketingEnum.FACEBOOK_ADS,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        accounts=FACEBOOK_ADS_ACCOUNTS,
        datalake_tables=FACEBOOK_ADS_TABLES
    )

    return sub_dag.build_tasks('clean')


def google_ads_clean_sub_dag(sub_dag_name):
    sub_dag = MarketingSubDag(
        clazz=MarketingEnum.GOOGLE_ADS,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        accounts=GOOGLE_ADS_ACCOUNTS,
        datalake_tables=GOOGLE_ADS_DATALAKE_TABLES
    )

    return sub_dag.build_tasks('clean')


def google_ads_load_to_pre_staging_sub_dag(sub_dag_name):
    sub_dag = MarketingSubDag(
        clazz=MarketingEnum.GOOGLE_ADS,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        datalake_tables=GOOGLE_ADS_DATALAKE_TABLES,
        fact_table=GOOGLE_ADS_FACT_TABLE,
        accounts=GOOGLE_ADS_ACCOUNTS
    )

    return sub_dag.build_tasks('pre_staging')


def google_ads_load_to_staging_sub_dag(sub_dag_name):
    sub_dag = MarketingSubDag(
        clazz=MarketingEnum.GOOGLE_ADS,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        dw_tables=GOOGLE_ADS_DW_TABLES,
        datalake_tables=GOOGLE_ADS_DATALAKE_TABLES
    )

    return sub_dag.build_tasks('staging')


def google_ads_load_to_dw_sub_dag(sub_dag_name):
    sub_dag = MarketingSubDag(
        clazz=MarketingEnum.GOOGLE_ADS,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        dw_tables=GOOGLE_ADS_DW_TABLES
    )

    return sub_dag.build_tasks('dw')


facebook_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=facebook_sub_dag,
    sub_dag_name="facebook-ads-raw-to-clean"
)

google_ads_clean_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=google_ads_clean_sub_dag,
    sub_dag_name='google-ads-raw-to-clean'
)

google_ads_load_to_pre_staging_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=google_ads_load_to_pre_staging_sub_dag,
    sub_dag_name='google-ads-load-to-pre-staging'
)

google_ads_load_to_staging_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=google_ads_load_to_staging_sub_dag,
    sub_dag_name='google-ads-load-to-staging'
)

google_ads_load_to_dw_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=google_ads_load_to_dw_sub_dag,
    sub_dag_name='google-ads-load-to-dw'
)

google_ads_clean_dag >> google_ads_load_to_pre_staging_dag >> google_ads_load_to_staging_dag >> google_ads_load_to_dw_dag
