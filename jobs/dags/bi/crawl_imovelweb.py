import json
from datetime import datetime, timedelta

from airflow.models import DAG
from qa_python_utils.default_logger import _logger

from jobs.base.base_dag import BaseDAG
from jobs.base.base_etl import BaseETL
from jobs.dags.util import environment as env

MAIN_DAG_NAME = 'crawling-houses-imovelweb'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = timedelta(days=3)

crawler_params = env.get_airflow_env_var('CRAWLING_HOUSES_PARAMS')


def submit_iw(**kwargs):
    max_crawl = kwargs.get('max_crawl', 1000000)
    states = kwargs.get('states')

    assert isinstance(max_crawl, int)
    assert isinstance(states, list)

    _logger.info('Starting job...')
    r = BaseETL.start_batch_job(
        job_name='crawl-imovelweb',
        job_queue='crawling-houses',
        job_definition='crawling-houses:8',
        command=['./crawlers/imovelweb.py', '--max_crawl', str(max_crawl), '--states'] + states
    )
    _logger.info('Finished with status {}. {}'.format(r.get('status'), '-'.join([r.get('jobId'), r.get('jobName')])))


dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1
)

BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-imovelweb',
    func_command=submit_iw,
    op_kwargs=json.loads(crawler_params)
)
