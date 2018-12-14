import json
from datetime import datetime

from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.batch import BatchClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.new_etl.crawlers.crawler_leads import CrawlerLeads
from bietlejuice.jobs.sensors.aws_batch_sensor import QuintoAndarAWSBatchSensor

env.set_airflow_var_to_local_env('EBDB')
logger = QuintoAndarLogger('crawling-leads-olx')

MAIN_DAG_NAME = 'crawling-leads-olx'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = '0 2 1/1 * *'

crawler_params = env.get_airflow_env_var('CRAWLING_HOUSES_PARAMS')

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
data_google_api_key = env.get_airflow_env_var('DATA_GOOGLE_API_KEY')
insert_leads_params = env.get_airflow_env_var('insert_leads_params')

NO_LEADS_MSG = 'There are no leads to insert.'


def insert_leads(**kwargs):
    ws = kwargs.get('ws')
    states = kwargs.get('states')
    delta_days = kwargs.get('since')

    crawler_leads = CrawlerLeads(s3_bucket=s3_bucket, google_maps_api_key=data_google_api_key)
    leads = crawler_leads.leads(ws=ws, states=states, delta_days=delta_days)

    if leads.empty:
        logger.info(NO_LEADS_MSG)
        return None

    logger.info('m=insert_leads, got {} leads from crawlers'.format(len(leads)))
    logger.info('m=insert_leads, state_size={}'.format(leads.groupby('state').size()))

    leads_cleaned = crawler_leads.cleaning(leads)
    if leads_cleaned.empty:
        logger.info(NO_LEADS_MSG)
        return None

    phones = crawler_leads.check_known_phone(90)
    regex_phone = r'(?P<code>\+\d{2})?(?P<number>\d+)'
    phones.phone_number = phones.phone_number.str.extract(regex_phone, expand=False).number

    leads_cleaned['phone_number'] = leads_cleaned.phones.apply(lambda p: eval(p)[0]).astype(str)
    leads_cleaned['known'] = leads_cleaned.phone_number.isin(phones.phone_number)
    leads_filtered = leads_cleaned[~leads_cleaned.known].sort_values(by='updated_on')
    if leads_filtered.empty:
        logger.info(NO_LEADS_MSG)
        return None

    logger.info('m=insert_leads, {} leads with new phone numbers'.format(len(leads_filtered)))
    logger.info('m=insert_leads, state_size={}'.format(leads_filtered.groupby('state').size()))

    # enrich lat and lng with ceps
    info = crawler_leads.enrich(leads_filtered.query("""lat.isnull() or lng.isnull()""").cep.unique())
    leads_enriched = leads_filtered.merge(info, how='left', left_on='cep', right_on='location')
    leads_enriched.lat = leads_enriched.lat.combine_first(leads_enriched.glat)
    leads_enriched.lng = leads_enriched.lng.combine_first(leads_enriched.glng)
    leads_enriched = leads_enriched.dropna(subset=['lat', 'lng'])

    # get to which region each lead belongs
    leads_enriched['regions'] = leads_enriched.apply(lambda row: crawler_leads.check_coverage(row.lat, row.lng), axis=1)

    # filter out units outside our coverage area
    leads_filtered = leads_enriched[
        (leads_enriched.regions > -1) &
        ((~leads_enriched.type.str.contains('casa')) | leads_enriched.regions.isin(crawler_leads.house_allowed))]
    if leads_filtered.empty:
        logger.info(NO_LEADS_MSG)
        return None
    logger.info('m=insert_leads, {} leads after filtering regions'.format(len(leads_filtered)))
    logger.info('m=insert_leads, state_size={}'.format(leads_filtered.groupby('state').size()))

    crawler_leads.send_leads(leads_filtered.iloc[:kwargs.get('max_leads')], ws=kwargs.get('ws'))


def submit_olx(**kwargs):
    max_crawl = kwargs.get('max_crawl', 1000000)
    states = kwargs.get('states')

    assert isinstance(max_crawl, int)
    assert isinstance(states, list)

    logger.info('Starting job...')
    r = BatchClient().start_batch_job(
        job_name='crawl-olx',
        job_queue='crawling-houses',
        job_definition='crawling-houses:10',
        command=['./crawlers/olx.py', '--max_crawl', str(max_crawl), '--states'] + states
    )
    logger.info('Finished with status {}. {}'.format(r.get('status'), '-'.join([r.get('jobId'), r.get('jobName')])))

    # get task instance
    ti = kwargs.get('ti')

    exec_date = str(datetime.date(kwargs.get('execution_date')))
    xcom.xcom_push(ti,
                   key='crawler_houses_olx_{}'.format(exec_date),
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

# operators
crawl_olx = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='crawl-olx',
    python_callable=submit_olx,
    op_kwargs=json.loads(crawler_params)
)

insert_leads = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='insert-leads',
    python_callable=insert_leads,
    op_kwargs=json.loads(insert_leads_params)
)

olx_success_test = QuintoAndarAWSBatchSensor(
    task_id='olx_success_test',
    poke_interval=20 * 60,
    timeout=5 * 3600,
    provide_context=True,
    xcom_task_id='crawl-olx'
)

crawl_olx >> olx_success_test >> insert_leads
