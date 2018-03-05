from datetime import datetime
import json
from jobs.dags.bi.base_dag import BaseDAG
from jobs.dags.util import environment as env
from jobs.new_etl.business_dim_etl import BusinessDimensionETL
from jobs.new_etl.marketing_dim_etl import MarketingDimensionETL
from jobs.new_etl.godfather import GodFather

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'GODFATHER')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
criteo_config = env.get_airflow_env_var('criteo')
google_config = env.get_airflow_env_var('ADWORDS_KEY')
facebook_config = env.get_airflow_env_var('FACEBOOK_KEY')
mkt_configs = dict()
mkt_configs['criteo'] = json.loads(criteo_config)
mkt_configs['facebook'] = json.loads(facebook_config)
mkt_configs['google'] = google_config
biz_etl = BusinessDimensionETL(bucket, datetime.now())
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


def ods_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_lead',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'lead', 'bucket': bucket, 'command': 'call ebdb.list_lead();'}
    )

    BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_contacts_and_prospects',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'contacts_and_prospects', 'bucket': bucket,
                   'command': 'call ebdb.list_contacts_and_prospects();'}
    )

    BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_imovel',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'property', 'bucket': bucket, 'command': 'call ebdb.list_imovel();',
                   'table_name': 'imovel'}
    )

    BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_region',
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'region', 'bucket': bucket, 'table_name': 'MapRegiao', 'add_timestamp': True,
                   'copy_to_clean': False}
    )

    BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_usuario',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'user', 'table_name': 'usuario', 'bucket': bucket,
                   'command': 'call ebdb.list_usuario();'}
    )

    BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_marketing_facebook_ads_costs',
        func_command=load_marketing_costs,
        op_kwargs={'dim_name': 'facebook'}
    )

    BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_marketing_google_adwords_costs',
        func_command=load_marketing_costs,
        op_kwargs={'dim_name': 'google'}
    )

    BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_marketing_criteo_costs',
        func_command=load_marketing_costs,
        op_kwargs={'dim_name': 'criteo'}
    )

    BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_affiliate_payments',
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'affiliate_payments', 'file_name': 'affiliate_payments.sql'}
    )

    BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_photo_job',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'photo_job', 'bucket': bucket, 'command': 'call ebdb.list_photo_job();'}
    )

    BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_contract',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'contract', 'command': 'call ebdb.list_contrato();'}
    )

    offer_to_s3_task = BaseDAG.get_quintoandar_python_operator(
        task_id='offer_to_s3',
        dag=local_dag,
        func_command=godfather_to_s3,
        op_kwargs={'table_name': 'offer'}
    )

    topic_to_s3_task = BaseDAG.get_quintoandar_python_operator(
        task_id='offer_topic_to_s3',
        dag=local_dag,
        func_command=godfather_to_s3,
        op_kwargs={'table_name': 'topic'}
    )

    offer_to_ods_task = BaseDAG.get_quintoandar_python_operator(
        task_id='offer_to_ods',
        dag=local_dag,
        func_command=load_athena_raw_query_to_ods,
        op_kwargs={'table_name': 'offer', 'query': """
                                                    select distinct
                                                        eo.*,
                                                        go.type,
                                                        go.first_sent_at,
                                                        go.last_sent_at,
                                                        gt.type as topic_type
                                                    from datalake_raw.ebdb_offer eo
                                                    join datalake_raw.godfather_offer go
                                                        on eo.godfatherid = go.id
                                                    left join datalake_raw.godfather_topic gt
                                                        on gt.offer_id = go.id
                                                    ;
                                                    """
                   }
    )

    pre_proposal_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_pre_proposal',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'pre_proposal', 'command': 'call ebdb.list_preproposta();'}
    )

    pre_proposta_aud_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_pre_proposal_aud',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'pre_proposal_AUD', 'table_name': 'PreProposta_AUD', 'copy_to_clean': False}
    )

    condicao_proposta_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_condition',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'condition', 'table_name': 'CondicaoProposta', 'copy_to_clean': False}
    )

    pre_proposta_condicao_proposta_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_pre_proposal_condition',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'pre_proposal_condition', 'table_name': 'PreProposta_CondicaoProposta',
                   'copy_to_clean': False}
    )

    BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_proposal',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'proposal', 'command': 'call ebdb.list_proposta();'}
    )

    BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_booking',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'booking', 'command': 'call ebdb.list_agendamento();'}
    )

    property_visit_information_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_property_visit_information',
        dag=local_dag,
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'property_visit_information', 'append': True,
                   'file_name': 'property_visit_information.sql'}
    )

    visits_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_visits',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'visit', 'command': 'call ebdb.list_visita();'}
    )

    BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_rental_flow',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'rental_flow', 'table_name': 'FluxoLocacao', 'copy_to_clean': False}
    )

    BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_region',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'agent_region', 'table_name': 'DadosAgente_Regiao', 'copy_to_clean': False}
    )

    property_visit_information_task >> visits_task
    offer_to_ods_task.set_upstream([offer_to_s3_task, topic_to_s3_task])
    pre_proposal_task >> pre_proposta_aud_task >> condicao_proposta_task >> pre_proposta_condicao_proposta_task

    return local_dag


dim_contract_task = BaseDAG.get_quintoandar_python_operator(
    task_id='DW_dim_contract',
    dag=main_dag,
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'contract'}
)

# dim_negotiation_task = BaseDAG.get_quintoandar_python_operator(
#     task_id='DW_dim_negotiation',
#     dag=main_dag,
#     func_command=load_dim_from_ods_to_dw,
#     op_kwargs={'dim_name': 'negotiation'}
# )

dim_offer_task = BaseDAG.get_quintoandar_python_operator(
    task_id='DW_dim_offer',
    dag=main_dag,
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'offer'}
)

dim_proposal_task = BaseDAG.get_quintoandar_python_operator(
    task_id='DW_dim_proposal',
    dag=main_dag,
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'proposal'}
)

booking_media_sources_task = BaseDAG.get_quintoandar_python_operator(
    task_id='ODS_booking_media_sources',
    dag=main_dag,
    func_command=load_athena_file_query_to_ods,
    op_kwargs={'table_name': 'booking_media_sources', 'file_name': 'extract_booking_media_sources.sql'}
)

dim_booking_task = BaseDAG.get_quintoandar_python_operator(
    task_id='DW_dim_booking',
    dag=main_dag,
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'booking',
               'post_command': "update dim_booking set visit_follow_up = null where visit_follow_up = ''"}
)

dim_visits_task = BaseDAG.get_quintoandar_python_operator(
    task_id='DW_dim_visits',
    dag=main_dag,
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'visit'}
)

ods_property_scheduling_task = BaseDAG.get_quintoandar_python_operator(
    task_id='ODS_liquidity_property_scheduling',
    dag=main_dag,
    func_command=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'property_scheduling', 'command': 'call ebdb.list_property_scheduling();'}
)

ods_potential_listings_tasks = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='ODS_supply_potential_listings',
    func_command=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'potential_listings',  'bucket': bucket, 'command': 'call ebdb.list_potential_listings(null);'}
)

listing_views_task = BaseDAG.get_quintoandar_python_operator(
    task_id='ODS_listing_views',
    dag=main_dag,
    func_command=load_athena_file_query_to_ods,
    op_kwargs={'table_name': 'listing_views', 'file_name': 'listing_views.sql'}
)

dim_lead_task = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_dim_lead',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_lead', 'bucket': bucket}
)

dim_contacts_and_prospects_task = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_contacts_and_prospects',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_contacts_and_prospects', 'bucket': bucket}
)

dim_property_task = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_dim_property',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_property', 'bucket': bucket}
)
dim_status_over_period_task = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_dim_property_status_over',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'property_status_over_period', 'bucket': bucket, 'insert_dummy': False}
)

dim_region_task = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_dim_region',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_region', 'bucket': bucket,
               'post_command': "update dim_region set dt_timestamp = '{}' where sk_region = -1;".format(
                   datetime.now().strftime('%Y-%m-%d'))}
)

dim_user_task = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_dim_user',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_user', 'bucket': bucket}
)

# dim_marketing_attribution_task = BaseDAG.get_quintoandar_python_operator(
#     dag=main_dag,
#     task_id='DW_dim_marketing_attribution',
#     func_command=load_dim_from_ods_to_dw,
#     op_kwargs={'dim_name': 'dim_marketing_attribution', 'bucket': bucket}
# )

dim_photo_job_task = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_dim_photo_job',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_photo_job', 'bucket': bucket}
)

fact_potential_listing_task = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_Fact_Supply_CAC',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'fact_supply_potential_listings', 'bucket': bucket, 'insert_dummy': False}
)

fact_property_scheduling_task = BaseDAG.get_quintoandar_python_operator(
    task_id='DW_fact_liquidity_property_scheduling',
    dag=main_dag,
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'liquidity_property_scheduling', 'is_fact': True, 'insert_dummy': False}
)

# flow
sources_dag = BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=ods_sub_dag,
    sub_dag_name='ODS'
)

# supply sources
sources_dag >> dim_lead_task >> fact_potential_listing_task
sources_dag >> dim_contacts_and_prospects_task >> fact_potential_listing_task
sources_dag >> dim_photo_job_task >> fact_potential_listing_task

# demand sources
booking_media_sources_task >> dim_booking_task
sources_dag >> dim_visits_task >> fact_property_scheduling_task
sources_dag >> dim_booking_task >> fact_property_scheduling_task
sources_dag >> dim_offer_task >> fact_property_scheduling_task
sources_dag >> dim_proposal_task >> fact_property_scheduling_task
sources_dag >> dim_contract_task >> fact_property_scheduling_task

# common sources
sources_dag >> dim_region_task
sources_dag >> dim_user_task
sources_dag >> dim_status_over_period_task
sources_dag >> dim_property_task

dim_property_task >> dim_status_over_period_task

dim_region_task >> fact_potential_listing_task
dim_user_task >> fact_potential_listing_task
dim_status_over_period_task >> fact_potential_listing_task

dim_region_task >> fact_property_scheduling_task
dim_user_task >> fact_property_scheduling_task
dim_status_over_period_task >> fact_property_scheduling_task

# facts
sources_dag >> ods_potential_listings_tasks >> fact_potential_listing_task
sources_dag >> ods_property_scheduling_task >> fact_property_scheduling_task

# rogue tasks
listing_views_task
