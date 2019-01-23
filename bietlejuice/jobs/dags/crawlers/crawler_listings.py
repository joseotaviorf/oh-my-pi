from airflow.models import DAG
from datetime import datetime
from qa_python_utils import QuintoAndarLogger

import bietlejuice.jobs.etl.powerbi as powerbi
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.crawlers.crawler_listings import CrawlerListings

MAIN_DAG_NAME = 'bi-crawler-listings'
MAIN_START_DATE = datetime(2018, 7, 30)
MAIN_SCHEDULE_INTERVAL = '0 2 * * 1-6'
PWBI_AUTH = env.get_airflow_env_var('PWBI_AUTH')
PWBI_SCHEMA = env.get_airflow_env_var('PWBI_SCHEMA')

logger = QuintoAndarLogger(MAIN_DAG_NAME)

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
data_google_api_key = env.get_airflow_env_var('DATA_GOOGLE_API_KEY')
google_maps_max_calls = env.get_airflow_env_var('GOOGLE_MAPS_MAX_CALLS')
_max_batch_size = env.get_airflow_env_var('CRAWLER_MAX_BATCH_SIZE')


def transform_crawler_data(bucket, api_key=None, api_daily_quota=30000, max_batch_size=100000):
    if api_key is None:
        logger.error('m=transform_crawler_data, msg=google api key not present')
        raise Exception('Variable missing')
    logger.info('m=transform_crawler_data, starting execution with quota={}'.format(api_daily_quota))
    crawled_listings = CrawlerListings(bucket, api_key, api_daily_quota, max_batch_size)
    crawled_listings.iterate_crawler_data()
    logger.info('m=transform_crawler_data, finished execution'.format(api_daily_quota))


def refresh_powerbi(**kwargs):
    powerbi_client = powerbi.PowerBIClient(PWBI_AUTH,
                                           PWBI_SCHEMA,
                                           kwargs['workspace_name'],
                                           kwargs['dataset_name'])
    powerbi_client.trigger_refresh()


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

crawler_listings = BaseDAG.build_python_operator(
    dag=dag,
    task_id='transform-crawler-data',
    python_callable=transform_crawler_data,
    op_kwargs={'bucket': s3_bucket, 'api_key': data_google_api_key, 'api_daily_quota': google_maps_max_calls,
               'max_batch_size': _max_batch_size}
)

refresh_market_index = BaseDAG.build_python_operator(
    dag=dag,
    task_id='Refresh_PowerBI_MarketIndex',
    python_callable=refresh_powerbi,
    op_kwargs={'workspace_name': 'Top-of-Funnel', 'dataset_name': 'Market Index'}
)

crawler_listings >> refresh_market_index
