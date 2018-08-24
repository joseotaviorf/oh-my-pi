import json
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.sensors.aws_batch_sensor import QuintoAndarAWSBatchSensor
from qa_python_utils.aws.batch import BatchClient
from qa_python_utils.default_logger import _logger

MAIN_DAG_NAME = 'crawler_houses'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = '0 0 1/3 * *'
MAX_TIMES_RUN = 20

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
crawler_params = env.get_airflow_env_var('CRAWLING_HOUSES_PARAMS')
dict_params = json.loads(crawler_params)


def start_crawler(**kwargs):
    max_crawl = kwargs.get('max_crawl', 1000000)
    states = kwargs.get('states')
    source = kwargs.get('source')
    ti = kwargs.get('ti')

    assert isinstance(max_crawl, int)
    assert isinstance(states, list)

    _logger.info('m=start_crawler, source={0}, msg=starting job...'.format(source))
    r = BatchClient().start_batch_job(
        job_name='crawl-{0}'.format(source),
        job_queue='crawling-houses',
        job_definition='crawling-houses:10',
        command=['./crawlers/{0}.py'.format(source), '--max_crawl', str(max_crawl), '--s3_bucket', s3_bucket,
                 '--states'] + states
    )
    _logger.info('m=start_crawler, status={}, job={}, msg=finished.'.format(r.get('status'), '-'.join(
        [r.get('jobId'), r.get('jobName')])))

    if source == 'proxies':
        exec_date = str(datetime.date(kwargs.get('execution_date')))
        xcom.xcom_push(ti,
                       key='crawler_houses_proxy_{}'.format(exec_date),
                       k_value=r.get('jobId'))


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

crawl_proxies = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-proxies',
    func_command=start_crawler,
    provide_context=True,
    op_kwargs=dict(dict_params.items() + ({'source': 'proxies'}).items())
)

crawl_imovelweb = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-imovelweb',
    func_command=start_crawler,
    provide_context=True,
    op_kwargs=dict(dict_params.items() + ({'source': 'imovelweb'}).items())
)

crawl_vivareal = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-vivareal',
    func_command=start_crawler,
    provide_context=True,
    op_kwargs=dict(dict_params.items() + ({'source': 'vivareal'}).items())
)

crawl_zap = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-zapimoveis',
    func_command=start_crawler,
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
