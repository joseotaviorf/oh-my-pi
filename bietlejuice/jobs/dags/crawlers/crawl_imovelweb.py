import json
from airflow.models import DAG
from datetime import datetime
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.batch import BatchClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env

MAIN_DAG_NAME = 'crawling-houses-imovelweb'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = '0 0 1/3 * *'

logger = QuintoAndarLogger(MAIN_DAG_NAME)

crawler_params = env.get_airflow_env_var('CRAWLING_HOUSES_PARAMS')


def submit_iw(**kwargs):
    max_crawl = kwargs.get('max_crawl', 1000000)
    states = kwargs.get('states')

    assert isinstance(max_crawl, int)
    assert isinstance(states, list)

    logger.info('Starting job...')
    r = BatchClient().start_batch_job(
        job_name='crawl-imovelweb',
        job_queue='crawling-houses',
        job_definition='crawling-houses:10',
        command=['./crawlers/imovelweb.py', '--max_crawl', str(max_crawl), '--states'] + states
    )
    logger.info('Finished with status {}. {}'.format(r.get('status'), '-'.join([r.get('jobId'), r.get('jobName')])))


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

BaseDAG.build_python_operator(
    dag=dag,
    task_id='crawl-imovelweb',
    python_callable=submit_iw,
    op_kwargs=json.loads(crawler_params)
)
