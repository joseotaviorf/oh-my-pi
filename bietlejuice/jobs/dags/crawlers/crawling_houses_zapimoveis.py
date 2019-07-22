import json
import re
from collections import OrderedDict
from datetime import datetime

import pandas as pd
from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.batch import BatchClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env, xcom
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.crawlers.crawler_entity import CrawlerEntity
from bietlejuice.jobs.sensors.aws_batch_sensor import QuintoAndarAWSBatchSensor

MAIN_DAG_NAME = 'crawling-houses-zapimoveis'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = '0 0 * * *'

logger = QuintoAndarLogger(MAIN_DAG_NAME)

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
crawler_params = env.get_airflow_env_var('CRAWLING_HOUSES_PARAMS')
data_google_api_key = env.get_airflow_env_var('DATA_GOOGLE_API_KEY')


def submit_zap(**kwargs):
    states = kwargs.get('states')
    execution_date = kwargs['execution_date'].strftime('%Y-%m-%d')

    assert isinstance(states, list)

    logger.info('Starting job...')
    r = BatchClient().start_batch_job(
        job_name='crawl-zapimoveis',
        job_queue='crawling-houses',
        job_definition='crawling-houses:10',
        memory=10240,
        command=['./crawlers/zapimoveis_crawler.py', '--listing_date', execution_date, '--states'] + states
    )
    logger.info('m=submit_vr, msg=Job {} with status {}'.format('-'.join([r.get('jobId'),
                                                                          r.get('jobName')]), r.get('status')))

    # get task instance
    ti = kwargs.get('ti')

    xcom.xcom_push(ti,
                   key='crawler_houses_zap_{}'.format(execution_date),
                   k_value=r.get('jobId'))


def enrich_and_move_to_clean(**kwargs):
    ws = 'zapimoveis'
    execution_date = kwargs.get('execution_date').strftime('%Y-%m-%d')
    query = BaseETL.get_query_from_file_name('{}/crawlers/get_scrapped_listings.sql'.format(DATALAKE_QUERIES_DIR))
    if not query:
        raise RuntimeError(
            'm=enrich_and_move_to_clean, msg=It was not found the query to extract data from datalake raw')
    crawler_entity = CrawlerEntity(s3_bucket, data_google_api_key, None)

    query = query.format(started_on=execution_date, ws=ws)
    leads = crawler_entity.athena_client.execute_query_and_return_dataframe(query)

    if leads.empty:
        logger.info("m=enrich_and_move_to_clean, msg=there are no leads to process")
    else:
        logger.info("m=enrich_and_move_to_clean, msg=got {} leads from datalake raw".format(len(leads)))
        regex = ", n. (\d+)"
        leads['nb_street'] = leads['street'].apply(
            lambda st: re.search(regex, str(st)).group(1) if re.search(regex, str(st)) else
            None)
        leads = crawler_entity.cleaning(leads)
        leads = leads.where((pd.notnull(leads)), None)

        r_cols = OrderedDict([
            ('id', str),
            ('website', str),
            ('url', str),
            ('http_status', str),
            ('crawled_on', str),
            ('updated_on', str),
            ('business', str),
            ('type', str),
            ('advertiser_name', str),
            ('advertiser_type', str),
            ('advertiser_id', str),
            ('phones', str),
            ('price', str),
            ('rent', str),
            ('condominium', str),
            ('iptu', str),
            ('total_area', str),
            ('useful_area', str),
            ('bedrooms', str),
            ('suites', str),
            ('toilets', str),
            ('garages', str),
            ('photos', str),
            ('description', str),
            ('unit_features', str),
            ('common_features', str),
            ('complementary_info', str),
            ('year_building', str),
            ('cep', str),
            ('lat', str),
            ('lng', str),
            ('street', str),
            ('nb_street', str),
            ('neighborhood', str),
            ('city', str),
            ('state', str),
            ('crawl_timestamp', str)
        ])

        crawler_entity.athena_client.create_parquet_from_df(
            key='clean/crawlers/ws={}/started_on={}/listings.parq'.format(ws, execution_date),
            df=leads,
            raw_columns=r_cols,
            clean_columns=r_cols)

        q = "alter table datalake_clean.crawlers add if not exists partition (ws='{}', started_on='{}')".format(
            ws,
            execution_date)
        try:
            crawler_entity.athena_client.execute_query_and_wait_for_results(q)
        except Exception as e:
            logger.error("m=enrich_and_move_to_clean, msg=couldn't create partition, e={}.".format(e))


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

crawl_zap = BaseDAG.build_python_operator(
    dag=dag,
    task_id='crawl-zapimoveis',
    python_callable=submit_zap,
    provide_context=True,
    op_kwargs=json.loads(crawler_params)
)

zap_success_test = QuintoAndarAWSBatchSensor(
    task_id='zap-success-test',
    poke_interval=20 * 60,
    timeout=22 * 3600,
    provide_context=True,
    xcom_task_id='crawl-zapimoveis'
)

move_to_clean = BaseDAG.build_python_operator(
    dag=dag,
    task_id='move-to-clean',
    python_callable=enrich_and_move_to_clean,
    provide_context=True
)

crawl_zap >> zap_success_test >> move_to_clean
