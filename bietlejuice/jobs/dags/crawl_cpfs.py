# coding=utf-8
import json
from datetime import datetime

from qa_python_utils.aws.batch import BatchClient
from qa_python_utils.default_logger import _logger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.crawlers.crawler_cpfs import CrawlerCPFs

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
crawl_cpfs_params = env.get_airflow_env_var('crawl_cpfs_params')

MAIN_DAG_NAME = 'crawling-cpfs'
MAIN_START_DATE = datetime(2018, 7, 1)
MAIN_SCHEDULE_INTERVAL = '0 16 * * 7'


def crawl_cpfs(**kwargs):
    delta_days = kwargs.get('delta_days', 0)
    ws = kwargs.get('ws', 'vivareal')
    limit = kwargs.get('limit', 0)

    crawler_cpfs = CrawlerCPFs(s3_bucket=s3_bucket, google_maps_api_key=None)
    locations_raw = crawler_cpfs.get_locations(ws=ws, delta_days=delta_days)
    if locations_raw.empty:
        _logger.info('m=get_locations, msg=no locations to crawl')
        return None

    _logger.info('m=crawl_cpfs, got {} locations from crawlers'.format(len(locations_raw)))

    last_date = crawler_cpfs.get_last_crawling_date(ws)
    suffix = '{}-{}.csv'.format(last_date, delta_days)
    filename = 'raw/crawled_cpfs/source/' + suffix
    if 0 < limit <= len(locations_raw):
        BaseETL.csv_to_s3(locations_raw.sample(n=limit), s3_bucket, filename)
    else:
        BaseETL.csv_to_s3(locations_raw, s3_bucket, filename)

    _logger.info('m=crawl_cpfs, starting job...')
    job = BatchClient().start_batch_job(
        job_name='crawl_' + suffix.split('.')[0].replace('-', '_'),
        job_queue='crawling-cpfs',
        job_definition='crawling-cpfs:2',
        command=['./crawlers/get_cpfs.py',
                 's3://{}/{}'.format(s3_bucket, filename),
                 '--max_crawl', '1000000', '--threads', '2']
    )

    _logger.info('m=crawl_cpfs, job submitted with status {}. {}'.format(
        job.get('status'), '-'.join([job.get('jobId'), job.get('jobName')])))


# main dag
dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    start_date=MAIN_START_DATE,
    schedule_interval=env.convert_to_utc_schedule(MAIN_SCHEDULE_INTERVAL)
)

# operators
BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-cpfs',
    func_command=crawl_cpfs,
    op_kwargs=json.loads(crawl_cpfs_params)
)
