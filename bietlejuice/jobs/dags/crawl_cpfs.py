# coding=utf-8

import json
from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from qa_python_utils.default_logger import _logger, logger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.crawlers.crawler_cpfs import CrawlerCPFs

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
data_google_api_key = env.get_airflow_env_var('DATA_GOOGLE_API_KEY')
crawl_cpfs_params = env.get_airflow_env_var('crawl_cpfs_params')

NO_LOCATIONS_MSG = 'no locations to crawl'


@logger
def crawl_cpfs(**kwargs):
    ws = kwargs.get('ws', 'vivareal')
    neighborhood = kwargs.get('neighborhood')
    delta_days = kwargs.get('delta_days', 3)
    limit = kwargs.get('limit', 500)

    crawler_cpfs = CrawlerCPFs(s3_bucket=s3_bucket, google_maps_api_key=data_google_api_key)
    locations_raw = crawler_cpfs.get_locations(ws=ws, delta_days=delta_days)
    if locations_raw.empty:
        _logger.info('m=get_locations, msg={}'.format(NO_LOCATIONS_MSG))
        return None

    _logger.info('m=crawl_cpfs, got {} locations from crawlers'.format(len(locations_raw)))

    locations_cleaned = crawler_cpfs.cleaning(locations_raw)
    locations_neighbors = crawler_cpfs.check_neighborhoods(locations_cleaned, neighborhood)
    locations_coverage = crawler_cpfs.check_locations_coverage(locations_neighbors)
    if locations_coverage.empty:
        _logger.info('m=crawl_cpfs, msg={}'.format(NO_LOCATIONS_MSG))
        return None

    _logger.info('m=crawl_cpfs, {} locations after filtering regions'.format(len(locations_coverage)))

    locations = crawler_cpfs.fill_in(locations_coverage, limit)
    if locations.empty:
        _logger.info('m=crawl_cpfs, msg={}'.format(NO_LOCATIONS_MSG))
        return None

    locations_unique = locations.groupby(['street_name', 'street_number']).size().reset_index()
    locations_unique.columns = ['street_name', 'street_number', 'n_listings']
    _logger.info('m=crawl_cpfs, saving seed with {} unique street_name and street_number'.format(len(locations_unique)))

    last_date = crawler_cpfs.get_last_crawling_date(ws)
    suffix = '{}-{}-{}.csv'.format(ws, last_date, delta_days)
    filename = 'raw/crawled_cpfs/source/' + suffix

    if len(locations) >= limit:
        BaseETL.csv_to_s3(locations.sample(n=limit), s3_bucket, filename)
    else:
        BaseETL.csv_to_s3(locations, s3_bucket, filename)

    _logger.info('m=crawl_cpfs, starting job...')
    crawler_cpfs.start_batch_job(
        job_name='crawl_' + suffix.split('.')[0].replace('-', '_'),
        job_queue='crawling-cpfs',
        job_definition='crawling-cpfs:1',
        exec_command=['./crawlers/get_cpfs.py',
                      's3://{}/{}'.format(s3_bucket, filename),
                      '--max_crawl', '1000000', '--threads', '2']
    )

    return locations


# main dag
dag = DAG(
    dag_id='crawling-cpfs',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 3, 25, 0, 0, 0),
    schedule_interval='@once',
    max_active_runs=1
)

# operators
PythonOperator(
    dag=dag,
    task_id='crawl-cpfs',
    python_callable=crawl_cpfs,
    op_kwargs=json.loads(crawl_cpfs_params)
)
