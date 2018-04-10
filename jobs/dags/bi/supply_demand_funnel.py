import json
from datetime import datetime

from jobs.base.base_dag import BaseDAG
from jobs.dags.bi.supply_demand_funnel import offer_subdag
from jobs.dags.util import environment as env
from jobs.new_etl.business_dim_etl import BusinessDimensionETL
from jobs.new_etl.godfather import GodFather
from jobs.new_etl.marketing_dim_etl import MarketingDimensionETL

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'GODFATHER')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
criteo_config = env.get_airflow_env_var('criteo')
google_config = dict()
google_config['sp_account'] = env.get_airflow_env_var('SP_ADWORDS_KEY')
google_config['display_account'] = env.get_airflow_env_var('DISPLAY_ADWORDS_KEY')
google_config['broad_location_account'] = env.get_airflow_env_var('BROAD_LOCATION_DSA_ADWORDS_KEY')
google_config['others_account'] = env.get_airflow_env_var('OTHER_CITIES_ADWORDS_KEY')
google_config['rj_account'] = env.get_airflow_env_var('RJ_ADWORDS_KEY')
google_config['institutional_account'] = env.get_airflow_env_var('INSTITUCIONAL_ADWORDS_KEY')
google_config['universal_app_account'] = env.get_airflow_env_var('UAC_ADWORDS_KEY')
facebook_config = env.get_airflow_env_var('FACEBOOK_KEY')
mkt_configs = dict()
mkt_configs['criteo'] = json.loads(criteo_config)
mkt_configs['facebook'] = json.loads(facebook_config)
mkt_configs['google'] = google_config
biz_etl = BusinessDimensionETL(bucket)
mkt_etl = MarketingDimensionETL(bucket, mkt_configs)

MAIN_DAG_NAME = 'bi-supply-demand-etl'
MAIN_START_DATE = datetime(2018, 3, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = '0 2 * * *'

# create main DAG definition
main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    description='ETL pipeline for the entire BI funnel',
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL
)


def godfather_to_s3(**kwargs):
    GodFather.to_s3(bucket, kwargs['table_name'])


def godfather_to_ods(**kwargs):
    GodFather.to_ods(kwargs['table_name'])


def extract_query_dim_from_ebdb_to_ods(**kwargs):
    biz_etl.extract_query_dim_from_ebdb_to_ods(
        dim_name=kwargs['dim_name'],
        command=kwargs['command'],
        table_name=None if 'table_name' not in kwargs else kwargs['table_name']
    )


def extract_table_dim_from_ebdb_to_ods(**kwargs):
    biz_etl.extract_table_dim_from_ebdb_to_ods(
        dim_name=kwargs['dim_name'],
        table_name=kwargs['table_name'],
        add_timestamp=False if 'add_timestamp' not in kwargs else kwargs['add_timestamp'],
        copy_to_clean=True if 'copy_to_clean' not in kwargs else kwargs['copy_to_clean']
    )


def load_athena_file_query_to_ods(**kwargs):
    biz_etl.load_athena_file_query_to_ods(
        table_name=kwargs['table_name'],
        file_name=kwargs['file_name'],
        append=False if 'append' not in kwargs else kwargs['append']
    )


def load_athena_raw_query_to_ods(**kwargs):
    biz_etl.load_athena_raw_query_to_ods(
        table_name=kwargs['table_name'],
        query=kwargs['query'],
        append=False if 'append' not in kwargs else kwargs['append']
    )


def load_dim_from_ods_to_dw(**kwargs):
    biz_etl.load_dim_from_ods_to_dw(
        dim_name=kwargs['dim_name'],
        insert_dummy=True if 'insert_dummy' not in kwargs else kwargs['insert_dummy'],
        is_fact=False if 'is_fact' not in kwargs else kwargs['is_fact'],
        pre_command=None if 'pre_command' not in kwargs else kwargs['pre_command'],
        post_command=None if 'post_command' not in kwargs else kwargs['post_command']
    )


def load_marketing_costs(**kwargs):
    mkt_etl.load_marketing_costs(
        dim_name=kwargs['dim_name']
    )


def materialize_view_ods(**kwargs):
    biz_etl.materialize_view_ods(
        view_name=kwargs['view_name'],
        append=False if 'append' not in kwargs else kwargs['append']
    )


def mock_run_dimension_tests():
    pass


def lead_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    lead = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_lead',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'lead', 'bucket': bucket, 'command': 'call ebdb.list_lead();'}
    )

    dim_lead = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='DW_dim_lead',
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'lead', 'bucket': bucket}
    )

    test_lead = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_lead',
        func_command=mock_run_dimension_tests
    )

    lead >> dim_lead >> test_lead

    return local_dag


def cap_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    contacts_and_prospects = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_contacts_and_prospects',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'contacts_and_prospects', 'bucket': bucket,
                   'command': 'call ebdb.list_contacts_and_prospects();'}
    )

    dim_contacts_and_prospects = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='DW_contacts_and_prospects',
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'contacts_and_prospects', 'bucket': bucket}
    )

    test_contacts_and_prospects = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_contacts_and_prospects',
        func_command=mock_run_dimension_tests
    )

    contacts_and_prospects >> dim_contacts_and_prospects >> test_contacts_and_prospects

    return local_dag


def photo_job_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    photo_job = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_photo_job',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'photo_job', 'bucket': bucket, 'command': 'call ebdb.list_photo_job();'}
    )

    dim_photo_job = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='DW_dim_photo_job',
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'photo_job', 'bucket': bucket}
    )

    test_photo_job = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_photo_job',
        func_command=mock_run_dimension_tests
    )

    photo_job >> dim_photo_job >> test_photo_job

    return local_dag


def region_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    agent_region = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_agent_region',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'agent_region', 'table_name': 'DadosAgente_Regiao', 'copy_to_clean': False}
    )

    region = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_region',
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'region', 'bucket': bucket, 'table_name': 'MapRegiao', 'add_timestamp': True,
                   'copy_to_clean': False}
    )

    dim_region = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='DW_dim_region',
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'region', 'bucket': bucket,
                   'post_command': "update dim_region set dt_timestamp = '{}' where sk_region = -1;".format(
                       datetime.now().strftime('%Y-%m-%d'))}
    )

    test_region = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_region',
        func_command=mock_run_dimension_tests
    )

    agent_region >> dim_region
    region >> dim_region
    dim_region >> test_region

    return local_dag


def user_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    user = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_user',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'user', 'table_name': 'usuario', 'bucket': bucket,
                   'command': 'call ebdb.list_usuario();'}
    )

    dim_user_task = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='DW_dim_user',
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'user', 'bucket': bucket}
    )

    test_user = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_user',
        func_command=mock_run_dimension_tests
    )

    user >> dim_user_task >> test_user

    return local_dag


def property_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    property_task = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_imovel',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'property', 'bucket': bucket, 'command': 'call ebdb.list_imovel();',
                   'table_name': 'imovel'}
    )

    affiliate = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_affiliate_payments',
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'affiliate_payments', 'file_name': 'affiliate_payments.sql'}
    )

    rental_flow = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_rental_flow',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'rental_flow', 'table_name': 'FluxoLocacao', 'copy_to_clean': False}
    )

    listing_views = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_listing_views',
        dag=local_dag,
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'listing_views', 'file_name': 'listing_views.sql'}
    )

    property_listing = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_property_listing',
        func_command=materialize_view_ods,
        op_kwargs={'view_name': 'property_listing'}
    )

    dim_property = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='DW_dim_property',
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'property', 'bucket': bucket}
    )

    dim_status_over_period = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='DW_dim_property_status_over',
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'property_status_over_period', 'bucket': bucket, 'insert_dummy': False}
    )

    test_property = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_property',
        func_command=mock_run_dimension_tests
    )

    listing_views
    rental_flow >> dim_property
    affiliate >> property_task
    property_task >> dim_property
    property_listing >> dim_property
    dim_property >> dim_status_over_period
    dim_status_over_period >> test_property

    return local_dag


def visit_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    visits = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_visits',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'visit', 'command': 'call ebdb.list_visita();'}
    )

    property_visit_information = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_property_visit_information',
        dag=local_dag,
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'property_visit_information', 'append': True,
                   'file_name': 'property_visit_information.sql'}
    )

    dim_visits = BaseDAG.get_quintoandar_python_operator(
        task_id='DW_dim_visits',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'visit'}
    )

    test_visits = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_visits',
        func_command=mock_run_dimension_tests
    )

    property_visit_information >> visits
    visits >> dim_visits
    dim_visits >> test_visits

    return local_dag


def offer_sub_dag(sub_dag_name):
    return offer_subdag.build(
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )


def proposal_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    proposal = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_proposal',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'proposal', 'command': 'call ebdb.list_proposta();'}
    )
    dim_negotiation = BaseDAG.get_quintoandar_python_operator(
        task_id='DW_dim_negotiation',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'negotiation'}
    )

    dim_proposal = BaseDAG.get_quintoandar_python_operator(
        task_id='DW_dim_proposal',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'proposal'}
    )

    test_proposal = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_proposal',
        func_command=mock_run_dimension_tests
    )

    proposal >> dim_proposal
    dim_proposal >> test_proposal
    dim_negotiation

    return local_dag


def contract_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    contract = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_contract',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'contract', 'command': 'call ebdb.list_contrato();'}
    )

    dim_contract = BaseDAG.get_quintoandar_python_operator(
        task_id='DW_dim_contract',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'contract'}
    )

    test_contract = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_contract',
        func_command=mock_run_dimension_tests
    )

    contract >> dim_contract
    dim_contract >> test_contract

    return local_dag


def booking_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    booking = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_booking',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'booking', 'command': 'call ebdb.list_agendamento();'}
    )

    booking_media_sources_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_booking_media_sources',
        dag=local_dag,
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'booking_media_sources', 'file_name': 'extract_booking_media_sources.sql'}
    )

    dim_booking_task = BaseDAG.get_quintoandar_python_operator(
        task_id='DW_dim_booking',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'booking',
                   'post_command': "update dim_booking set visit_follow_up = null where visit_follow_up = ''"}
    )

    test_booking = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_booking',
        func_command=mock_run_dimension_tests
    )

    booking >> dim_booking_task
    booking_media_sources_task >> dim_booking_task
    dim_booking_task >> test_booking

    return local_dag


def marketing_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    facebook = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_marketing_facebook_ads_costs',
        func_command=load_marketing_costs,
        op_kwargs={'dim_name': 'facebook'}
    )

    adwords = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_marketing_google_adwords_costs',
        func_command=load_marketing_costs,
        op_kwargs={'dim_name': 'google'}
    )

    # criteo = BaseDAG.get_quintoandar_python_operator(
    #     dag=local_dag,
    #     task_id='ODS_marketing_criteo_costs',
    #     func_command=load_marketing_costs,
    #     op_kwargs={'dim_name': 'criteo'}
    # )

    dim_marketing_attribution = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='DW_dim_marketing_attribution',
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'marketing_attribution', 'bucket': bucket}
    )

    test_marketing = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_marketing',
        func_command=mock_run_dimension_tests
    )

    facebook >> test_marketing
    adwords >> test_marketing
    # criteo >> test_marketing
    dim_marketing_attribution

    return local_dag


ods_property_scheduling = BaseDAG.get_quintoandar_python_operator(
    task_id='ODS_liquidity_property_scheduling',
    dag=main_dag,
    func_command=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'property_scheduling', 'command': 'call ebdb.list_property_scheduling();'}
)

ods_potential_listings = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='ODS_supply_potential_listings',
    func_command=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'potential_listings', 'bucket': bucket,
               'command': 'call ebdb.list_potential_listings(null);'}
)

ods_supply = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='ODS_supply',
    func_command=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'fact_supply', 'bucket': bucket,
               'command': 'call ebdb.list_fact_supply(null);'}
)

fact_potential_listing = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_Fact_Supply_CAC',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'supply_potential_listings', 'is_fact': True, 'bucket': bucket, 'insert_dummy': False}
)

fact_property_scheduling = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_fact_liquidity_property_scheduling',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'liquidity_property_scheduling', 'is_fact': True, 'bucket': bucket, 'insert_dummy': False}
)

# flow
lead_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=lead_sub_dag,
    sub_dag_name='Lead'
)

cap_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=cap_sub_dag,
    sub_dag_name='CAP'
)

photo_job_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=photo_job_sub_dag,
    sub_dag_name='PhotoJob'
)

region_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=region_sub_dag,
    sub_dag_name='Region'
)

user_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=user_sub_dag,
    sub_dag_name='User'
)

property_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=property_sub_dag,
    sub_dag_name='Property'
)

visit_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=visit_sub_dag,
    sub_dag_name='Visit'
)

offer_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=offer_sub_dag,
    sub_dag_name='Offer'
)

proposal_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=proposal_sub_dag,
    sub_dag_name='Proposal'
)

contract_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=contract_sub_dag,
    sub_dag_name='Contract'
)

booking_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=booking_sub_dag,
    sub_dag_name='Booking'
)

marketing_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=marketing_sub_dag,
    sub_dag_name='Marketing'
)

ods_potential_listings.set_upstream([lead_dag, cap_dag, photo_job_dag, region_dag, user_dag, property_dag,
                                     marketing_dag])
ods_property_scheduling.set_upstream([booking_dag, visit_dag, offer_dag, proposal_dag, contract_dag, region_dag,
                                      user_dag, property_dag])

ods_potential_listings >> fact_potential_listing
ods_supply >> fact_potential_listing
ods_property_scheduling >> fact_property_scheduling
