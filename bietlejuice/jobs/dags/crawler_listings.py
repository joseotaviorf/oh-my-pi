from airflow.models import DAG
from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.crawlers.crawler_listings import CrawlerListings
from qa_python_utils.default_logger import _logger

MAIN_DAG_NAME = 'bi-crawler-listings'
MAIN_START_DATE = datetime(2018, 7, 2)
MAIN_SCHEDULE_INTERVAL = '0 2 * * *'

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
data_google_api_key = env.get_airflow_env_var('DATA_GOOGLE_API_KEY')
google_maps_max_calls = env.get_airflow_env_var('GOOGLE_MAPS_MAX_CALLS')


def transform_crawler_data(bucket, api_key=None, api_daily_quota=30000):
    if api_key is None:
        _logger.error('google api key not present')
        raise Exception('Variable missing')
    _logger.info('m=transform_crawler_data, starting execution with quota={}'.format(api_daily_quota))
    crawled_listings = CrawlerListings(bucket, api_key, api_daily_quota)
    crawled_listings.transform_crawler_data()
    _logger.info('m=transform_crawler_data, finished execution'.format(api_daily_quota))


dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=env.convert_to_utc_schedule(MAIN_SCHEDULE_INTERVAL),
    max_active_runs=1
)

BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='transform-crawler-data',
    func_command=transform_crawler_data,
    op_kwargs={'bucket': s3_bucket, 'api_key': data_google_api_key, 'api_daily_quota': google_maps_max_calls}
)
