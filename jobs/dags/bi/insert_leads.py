from datetime import datetime

import numpy as np
import pandas as pd
from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from qa_python_utils.default_logger import _logger

from jobs.etl.crawlers.crawler_leads import CrawlerLeads


def insert_leads(**kwargs):
    NO_LEADS_MSG = 'There are no leads to insert.'

    crawler_leads = CrawlerLeads()
    leads = crawler_leads.leads(
        ws=kwargs.get('ws'),
        states=kwargs.get('states'),
        delta_days=kwargs.get('since'))
    if leads.empty:
        _logger.info(NO_LEADS_MSG)
        return None

    leads = crawler_leads.cleaning(leads)
    if leads.empty:
        _logger.info(NO_LEADS_MSG)
        return None

    # enrich lat and lng with ceps
    info = crawler_leads.enrich(leads.query("""lat.isnull() or lng.isnull()""").cep.unique())
    leads = leads.merge(info, how='left', left_on='cep', right_on='location')
    leads.lat = leads.lat.combine_first(leads.glat)
    leads.lng = leads.lng.combine_first(leads.glng)

    # get to which region each lead belongs
    leads['regions'] = leads.apply(lambda row: crawler_leads.check_coverage(row.lat, row.lng), axis=1)

    # filter out units outside our coverage area
    leads = leads[(leads.regions > -1) & ((leads.type != 'casa') | leads.regions.isin(crawler_leads.house_allowed))]
    if leads.empty:
        _logger.info(NO_LEADS_MSG)
        return None

    # get known phones from last 6 months
    phones = crawler_leads.check_known_phone(leads, delta_days=180)
    leads['known'] = pd.Series(
        np.array([np.array(p) for p in leads.phones.apply(eval).values]).ravel()).isin(
        phones.phone_number.unique()).values

    # send leads not known
    leads = leads[~leads.known]
    if leads.empty:
        _logger.info(NO_LEADS_MSG)
        return None

    crawler_leads.send_leads(leads.iloc[:kwargs.get('max_leads')], ws=kwargs.get('olx'))

    return leads


dag = DAG(
    dag_id='crawling-houses-insert-leads',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 3, 25, 18, 0, 0),
    schedule_interval='0 1 * * *',
    max_active_runs=1
)

# operators
PythonOperator(
    dag=dag,
    task_id='insert-leads',
    python_callable=insert_leads,
    op_kwargs={'ws': 'olx', 'states': ['sp', 'rj'], 'since': 1, 'max_leads': 200}
)
