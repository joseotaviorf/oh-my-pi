from datetime import datetime, timedelta
from bietlejuice.jobs.dags.crawlers import start_batch_job, STATES
from qa_python_utils.default_logger import _logger
from bietlejuice.jobs.base.base_dag import BaseDAG
from airflow.models import DAG

MAIN_DAG_NAME = 'crawling-houses-imovelweb'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = timedelta(days=3)


def submit_iw():
    _logger.info('Starting job...')
    r = start_batch_job(
        job_name='crawl-imovelweb',
        job_queue='crawling-houses',
        job_definition='crawling-houses:8',
        command=['./crawlers/imovelweb.py', '--max_crawl', '1000000', '--states'] + STATES
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
    func_command=submit_iw
)
