import cStringIO

import json
from airflow.models import DAG
from datetime import datetime

import bietlejuice.jobs.etl.powerbi as powerbi
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.crawlers.crawler_entity import CrawlerEntity

MAIN_DAG_NAME = 'crawling-check-exclusives'
MAIN_START_DATE = datetime(2018, 6, 12)
MAIN_SCHEDULE_INTERVAL = '0 6 1/1 * *'
PWBI_AUTH = env.get_airflow_env_var('PWBI_AUTH')
PWBI_SCHEMA = env.get_airflow_env_var('PWBI_SCHEMA')

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
check_exclusive_rules = env.get_airflow_env_var('check_exclusive_rules')


def check_exclusives(**kwargs):
    """
    Job that will populate the crawled_exclusive table on datalake_raw. Every time the crawlers run, this job will
    try to match, following some approximation rules, exclusive listings from QuintoAndar to crawled external listings.
    Then it saves to s3 only matches that did not occurred before.

    Args:
        :param kwargs: dictionary containing the approximation rules for matches.
    """
    distance_m = kwargs.get('distance_m', 15)
    condo_percent = kwargs.get('condo_percent', 0.05)
    rent_percent = kwargs.get('rent_percent', 0.15)
    area_percent = kwargs.get('area_percent', 0.05)

    crawler_entity = CrawlerEntity(s3_bucket, google_maps_api_key=None, get_polygons=False, get_house_allowed=False)

    q = BaseETL.get_query_from_file_name('{}/crawlers/match_exclusives.sql'.format(DATALAKE_QUERIES_DIR))

    q = q.format(
        distance_m=distance_m,
        condo_percent=condo_percent,
        rent_percent=rent_percent,
        area_percent=area_percent)

    matches = crawler_entity.athena_client.execute_query_and_return_dataframe(q)

    past_matches = crawler_entity.athena_client.execute_query_and_return_dataframe(
        """select id, id_externo, website from datalake_raw.crawled_exclusive""")

    m_key = ['id', 'id_externo', 'website']
    merged = matches.merge(past_matches, on=m_key, how='outer', indicator=True)
    merged = merged[merged['_merge'] == 'left_only']
    matches = matches.merge(merged[m_key], on=m_key, how='right')
    if matches.empty:
        return None

    try:
        exec_date = str(datetime.date(kwargs['execution_date']))
    except Exception:
        exec_date = datetime.now().strftime('%Y-%m-%d')

    matches.loc[:, 'match_em'] = exec_date
    filename = 'raw/crawled_exclusive/matches-{}.csv'.format(exec_date)

    obj = matches.to_csv(index=False, encoding='utf8')
    io = cStringIO.StringIO(obj)
    BaseETL.obj_to_s3(io, s3_bucket, filename)


def refresh_powerbi(**kwargs):
    powerbi_client = powerbi.PowerBIClient(PWBI_AUTH,
                                           PWBI_SCHEMA,
                                           kwargs['workspace_name'],
                                           kwargs['dataset_name'])
    powerbi_client.trigger_refresh()


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

# operators
exclusives = BaseDAG.build_python_operator(
    dag=dag,
    task_id='crawling-check-exclusives',
    python_callable=check_exclusives,
    op_kwargs=json.loads(check_exclusive_rules)
)

refresh_exclusives = BaseDAG.build_python_operator(
    dag=dag,
    task_id='Refresh_PowerBI_Exclusives',
    python_callable=refresh_powerbi,
    op_kwargs={'workspace_name': 'Top-of-Funnel', 'dataset_name': 'Exclusives'}
)

exclusives >> refresh_exclusives
