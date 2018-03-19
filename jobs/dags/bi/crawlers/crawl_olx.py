from datetime import datetime, timedelta
from jobs.dags.bi.crawlers import start_batch_job, STATES
from qa_python_utils.default_logger import _logger
from jobs.base.base_dag import BaseDAG

MAIN_DAG_NAME = 'crawling-houses-olx'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = timedelta(hours=18)


def submit_olx():
    _logger.info('Starting job...')
    r = start_batch_job(
        job_name='crawl-olx',
        job_queue='crawling-houses',
        job_definition='crawling-houses:8',
        command=['./crawlers/olx.py', '--max_crawl', '1000000', '--states'] + STATES
    )
    _logger.info('Finished with status {}. {}'.format(r.get('status'), '-'.join([r.get('jobId'), r.get('jobName')])))


dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL
)

op = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-olx',
    func_command=submit_olx
)

op
