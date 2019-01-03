import json
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.batch import BatchClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.sensors.aws_batch_sensor import QuintoAndarAWSBatchSensor

MAIN_DAG_NAME = 'crawler_houses'
MAIN_START_DATE = datetime(2018, 8, 24)
MAIN_SCHEDULE_INTERVAL = '0 0 1/3 * *'

logger = QuintoAndarLogger(MAIN_DAG_NAME)

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
crawler_params = env.get_airflow_env_var('CRAWLING_HOUSES_PARAMS')
dict_params = json.loads(crawler_params)


def crawl_proxy(**kwargs):
    source = kwargs.get('source')

    # start crawling
    cmd = ['./crawlers/{0}.py'.format(source), '--s3_bucket', s3_bucket]

    r = start_crawler(cmd, **kwargs)

    # get task instance
    ti = kwargs.get('ti')

    exec_date = str(datetime.date(kwargs.get('execution_date')))
    xcom.xcom_push(ti,
                   key='crawler_houses_proxy_{}'.format(exec_date),
                   k_value=r.get('jobId'))


def crawl_houses(**kwargs):
    max_crawl = kwargs.get('max_crawl', 1000000)
    states = kwargs.get('states')
    source = kwargs.get('source')

    assert isinstance(max_crawl, int)
    assert isinstance(states, list)

    cmd = ['./crawlers/{0}.py'.format(source), '--s3_bucket', s3_bucket, '--max_crawl', str(max_crawl),
           '--states'] + states

    r = start_crawler(cmd, **kwargs)


def start_crawler(cmd, **kwargs):
    source = kwargs.get('source')

    logger.info('m=start_crawler, source={0}, msg=starting job...'.format(source))
    r = BatchClient().start_batch_job(
        job_name='crawl-{0}'.format(source),
        job_queue='crawling-houses',
        job_definition='crawling-houses:10',
        command=cmd
    )
    logger.info('m=start_crawler, status={}, job={}, msg=finished.'.format(r.get('status'), '-'.join(
        [r.get('jobId'), r.get('jobName')])))

    return r


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
    catchup=True
)

crawl_proxies = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-proxies',
    python_callable=crawl_proxy,
    provide_context=True,
    op_kwargs={'source': 'proxies'}
)

crawl_imovelweb = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-imovelweb',
    python_callable=crawl_houses,
    provide_context=True,
    op_kwargs=dict(dict_params.items() + ({'source': 'imovelweb'}).items())
)

crawl_vivareal = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-vivareal',
    python_callable=crawl_houses,
    provide_context=True,
    op_kwargs=dict(dict_params.items() + ({'source': 'vivareal'}).items())
)

crawl_zap = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-zapimoveis',
    python_callable=crawl_houses,
    provide_context=True,
    op_kwargs=dict(dict_params.items() + ({'source': 'zapimoveis'}).items())
)

proxy_success_test = QuintoAndarAWSBatchSensor(
    task_id='proxy_success_test',
    poke_interval=30,
    timeout=3600,
    provide_context=True,
    xcom_task_id='crawl-proxies'
)

# flow
airflow_helpers.chain(crawl_proxies, proxy_success_test)
proxy_success_test.set_downstream([crawl_imovelweb, crawl_vivareal, crawl_zap])
