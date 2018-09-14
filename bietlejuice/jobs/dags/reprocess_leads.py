import json
import math
import os
from datetime import datetime

from qa_python_utils.default_logger import _logger
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl import LEAD_VARIANT_CONFIG_DIR
from bietlejuice.jobs.new_etl.leads.leads_processor import LeadsProcessor

MAIN_DAG_NAME = 'reprocess-leads'
MAIN_START_DATE = datetime(2018, 7, 3)
MAIN_SCHEDULE_INTERVAL = '@once'

env.set_airflow_var_to_local_env('EBDB')

reprocess_leads_variant = env.get_airflow_env_var('reprocess_leads_variant')


@logger
def get_variant_config(variant):
    filepath = os.path.join(LEAD_VARIANT_CONFIG_DIR, '{}.json'.format(variant.lower()))
    if not os.path.isfile(filepath):
        raise IOError('m=get_variant_config, msg=Could not load {} for variant {}. '
                      'You should point to an existent variant or create a new one.'.format(filepath, variant))

    with open(filepath) as f:
        variant_config = json.load(f)
        if variant_config.get('variant') != variant:
            raise ValueError('m=get_variant_config, msg=Variant name does not match with config file.')
        return variant_config

    raise Exception


def reprocess_leads(variant):
    variant_config = get_variant_config(variant)

    contact_options = variant_config.get('contact', {})
    lead_options = variant_config.get('lead', {})
    variant = variant_config.get('variant', 'UNMAPPED')
    variant_group = variant_config.get('variant_group', 'UNMAPPED')
    recency_bucket = variant_config.get('recency_bucket', False)
    size_limit = variant_config.get('size_limit')
    check_coverage = variant_config.get('check_coverage', False)

    processor = LeadsProcessor()
    leads = processor.read_leads(
        origin=lead_options.get('origin'),
        status=lead_options.get('status'),
        reason=lead_options.get('reason'),
        interval=lead_options.get('interval'),
        unit=lead_options.get('unit'))

    old_reprocessed = processor.get_reprocessed()

    _logger.info('m=reprocess_leads, msg=filtering out already reprocessed leads.')
    processed = leads.merge(old_reprocessed, on='id', how='left').query('reprocessed_at.isnull()')

    if contact_options:
        contacts = processor.get_contacts(
            week_interval=contact_options.get('week_interval'),
            status_in=contact_options.get('status_in'),
            reason_in=contact_options.get('reason_in'),
            statuses=contact_options.get('statuses'),
            reasons=contact_options.get('reasons'))

        _logger.info('m=reprocess_leads, msg=filtering out already contacted phone numbers.')
        blacklist = set()
        for c_phone in [c for c in processed.columns if c.startswith('telefoneAnunciante')]:
            contacted = processed.merge(contacts, left_on=c_phone, right_on='phone', how='left')
            indicator = ((contacted.contacted == 1) & (contacted.contact_time >= contacted.atualizadoEm))
            blacklist |= set(contacted.loc[indicator, 'id'].tolist())

        processed = processed[~processed.id.isin(list(blacklist))]

    if check_coverage:
        region_id = processed.apply(lambda row: processor.check_coverage(row.lat, row.lng), axis=1)

        _logger.info('m=reprocess_leads, msg=filtering out locations outside coverage area.')
        processed = processed[~region_id.isnull() & (region_id != -1)]

    processed['origem'] = 'Reprocessado'
    processed['infosExtras'] = processed.id.apply(lambda x: '{};{};{}'.format(x, variant, variant_group))
    if recency_bucket:
        buckets = (((datetime.utcnow().date() - processed.atualizadoEm.dt.date).dt.days / processor.get_unit_divisor()).
                   apply(math.floor).astype(int))
        processed['infosExtras'] = processed['infosExtras'] + ';' + buckets.astype(str) + lead_options.get('unit')

    if size_limit is not None and len(processed) > size_limit:
        _logger.info('m=reprocess_leads, msg=apply limit to insertion ({}/{} new leads).'.format(
            size_limit, len(processed)))
        processed = processed.sample(n=size_limit)

    _logger.info('m=reprocess_leads, msg=sending {} new leads.'.format(len(processed)))
    processor.send_leads(processed)
    _logger.info('m=reprocess_leads, msg=done!')


dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    wait_for_downstream=False,
    depends_on_past=False,
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=False
)

# operators
BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='reprocess-leads',
    python_callable=reprocess_leads,
    op_kwargs={'variant': reprocess_leads_variant}
)
