import json
from datetime import datetime

import numpy as np
import pandas as pd
from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from qa_python_utils.default_logger import _logger

from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.crawlers.crawler_leads import CrawlerLeads

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
        _logger.info(NO_LEADS_MSG)
        return None

    _logger.info('m=insert_leads, got {} leads from crawlers'.format(len(leads)))
    _logger.info('m=insert_leads, state_size={}'.format(leads.groupby('state').size()))

    leads_cleaned = crawler_leads.cleaning(leads)
    if leads_cleaned.empty:
        _logger.info(NO_LEADS_MSG)
        return None

    # get known phones from last 3 months
    phones = crawler_leads.check_known_phone(leads_cleaned, delta_days=90)
    leads_cleaned['known'] = pd.Series(
        np.array([np.array(p) for p in leads_cleaned.phones.apply(eval).values]).ravel()).isin(
        phones.phone_number.unique()).values

    # send leads not known
    leads_filtered = leads_cleaned[~leads_cleaned.known].sort_values(by='updated_on')
    if leads_filtered.empty:
        _logger.info(NO_LEADS_MSG)
        return None

    _logger.info('m=insert_leads, {} leads with new phone numbers'.format(len(leads_filtered)))
    _logger.info('m=insert_leads, state_size={}'.format(leads_filtered.groupby('state').size()))

    # enrich lat and lng with ceps
    info = crawler_leads.enrich(leads_filtered.query("""lat.isnull() or lng.isnull()""").cep.unique())
    leads_enriched = leads_filtered.merge(info, how='left', left_on='cep', right_on='location')
    leads_enriched.lat = leads_enriched.lat.combine_first(leads_enriched.glat)
    leads_enriched.lng = leads_enriched.lng.combine_first(leads_enriched.glng)

    # get to which region each lead belongs
    leads_enriched['regions'] = leads_enriched.apply(lambda row: crawler_leads.check_coverage(row.lat, row.lng), axis=1)

    # filter out units outside our coverage area
    leads_filtered = leads_enriched[
        (leads_enriched.regions > -1) &
        (
                (~leads_enriched.type.str.contains('casa')) |
                leads_enriched.regions.isin(crawler_leads.house_allowed)
        )
        ]
    if leads_filtered.empty:
        _logger.info(NO_LEADS_MSG)
        return None
    _logger.info('m=insert_leads, {} leads after filtering regions'.format(len(leads_filtered)))
    _logger.info('m=insert_leads, state_size={}'.format(leads_filtered.groupby('state').size()))

    crawler_leads.send_leads(leads_filtered.iloc[:kwargs.get('max_leads')], ws=kwargs.get('ws'))

    return leads


dag = DAG(
    dag_id='crawling-houses-insert-leads',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 3, 25, 20, 0, 0),
    schedule_interval='0 1 * * *',
    max_active_runs=1
)

# operators
PythonOperator(
    dag=dag,
    task_id='insert-leads',
    python_callable=insert_leads,
    op_kwargs=json.loads(insert_leads_params)
)
