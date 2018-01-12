from datetime import time, datetime, timedelta
from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from jobs.dags.util import environment as env
from jobs.new_etl.business_dim_etl import BusinessDimensionETL


env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
now = datetime.now()

biz_etl = BusinessDimensionETL(bucket, now)

# create DAG definition
dag = DAG(
    dag_id='bi-liquidity-scheduled-properties',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 1, 1, 2, 0, 0),
    schedule_interval=timedelta(days=1),
    max_active_runs=1
)

# Contract Dimension
contract = PythonOperator(
    dag=dag,
    task_id='ODS_contract',
    python_callable=biz_etl.extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'contract', 'command': 'call ebdb.list_contrato();'}
)
dim_contract = PythonOperator(
    dag=dag,
    task_id='DW_dim_contract',
    python_callable=biz_etl.load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'contract'}
)
# Negotiation Dimension
negotiation = PythonOperator(
    dag=dag,
    task_id='ODS_negotiation',
    python_callable=biz_etl.extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'negotiation', 'command': 'call ebdb.list_negociacao();'}
)
dim_negotiation = PythonOperator(
    dag=dag,
    task_id='DW_dim_negotiation',
    python_callable=biz_etl.load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'negotiation'}
)
# PreProposal Dimension
pp = PythonOperator(
    dag=dag,
    task_id='ODS_pre_proposal',
    python_callable=biz_etl.extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'pre_proposal', 'command': 'call ebdb.list_preproposta();'}
)
pp_aud = PythonOperator(
    dag=dag,
    task_id='ODS_pre_proposal_aud',
    python_callable=biz_etl.extract_table_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'pre_proposal_AUD', 'table_name': 'PreProposta_AUD', 'copy_to_clean': False}
)
cp = PythonOperator(
    dag=dag,
    task_id='ODS_condition',
    python_callable=biz_etl.extract_table_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'condition', 'table_name': 'CondicaoProposta', 'copy_to_clean': False}
)
pp_cp = PythonOperator(
    dag=dag,
    task_id='ODS_pre_proposal_condition',
    python_callable=biz_etl.extract_table_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'pre_proposal_condition', 'table_name': 'PreProposta_CondicaoProposta',
               'copy_to_clean': False}
)
dim_p = PythonOperator(
    dag=dag,
    task_id='DW_dim_pre_proposal',
    python_callable=biz_etl.load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'pre_proposal'}
)
# Proposal Dimension
proposal = PythonOperator(
    dag=dag,
    task_id='ODS_proposal',
    python_callable=biz_etl.extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'proposal', 'command': 'call ebdb.list_proposta();'}
)
dim_proposal = PythonOperator(
    dag=dag,
    task_id='DW_dim_proposal',
    python_callable=biz_etl.load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'proposal'}
)
# Booking Dimension
booking = PythonOperator(
    dag=dag,
    task_id='ODS_booking',
    python_callable=biz_etl.extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'booking', 'command': 'call ebdb.list_agendamento();'}
)
dim_booking = PythonOperator(
    dag=dag,
    task_id='DW_dim_booking',
    python_callable=biz_etl.load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'booking',
               'post_command': 'update dim_booking set visit_follow_up = null where visit_follow_up = ""'}
)
# Visits Dimension
visit = PythonOperator(
    dag=dag,
    task_id='ODS_visits',
    python_callable=biz_etl.extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'visit', 'command': 'call ebdb.list_visita();'}
)
dim_visit = PythonOperator(
    dag=dag,
    task_id='DW_dim_visits',
    python_callable=biz_etl.load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'visit'}
)
# Rental Flow Dimension
rental_flow = PythonOperator(
    dag=dag,
    task_id='ODS_rental_flow',
    python_callable=biz_etl.extract_table_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'rental_flow', 'table_name': 'FluxoLocacao'}
)
# Agent Region Dimension
agent_region = PythonOperator(
    dag=dag,
    task_id='ODS_region',
    python_callable=biz_etl.extract_table_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'agent_region', 'table_name': 'DadosAgente_Regiao'}
)
# Booking Media Sources Dimension
booking_media_sources = PythonOperator(
    dag=dag,
    task_id='ODS_booking_media_sources',
    python_callable=biz_etl.load_athena_query_to_ods,
    op_kwargs={'dim_name': 'booking_media_sources',
               'file_name': './db/2.datalake/queries/extract_booking_media_sources.sql'}
)

# Property Visit Information Dimension
property_visit_information = PythonOperator(
    dag=dag,
    task_id='ODS_property_visit_information',
    python_callable=biz_etl.load_athena_query_to_ods,
    op_kwargs={'dim_name': 'property_visit_information',
               'append': True,
               'file_name': './db/2.datalake/queries/property_visit_information.sql'}
)

# Scheduled Properties Fact
property_scheduling = PythonOperator(
    dag=dag,
    task_id='ODS_liquidity_property_scheduling',
    python_callable=biz_etl.extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'property_scheduling', 'command': 'call ebdb.list_property_scheduling();'}
)
fact_property_scheduling = PythonOperator(
    dag=dag,
    task_id='DW_fact_liquidity_property_scheduling',
    python_callable=biz_etl.load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'liquidity_property_scheduling', 'is_fact': True, 'insert_dummy': False}
)

# flow:
contract >> property_scheduling
negotiation >> property_scheduling
pp >> property_scheduling
pp_aud >> property_scheduling
cp >> property_scheduling
pp_cp >> property_scheduling
proposal >> property_scheduling
booking >> property_scheduling
property_visit_information >> visit
visit >> property_scheduling
rental_flow >> property_scheduling
agent_region >> property_scheduling

booking_media_sources >> dim_booking

property_scheduling >> dim_contract
property_scheduling >> dim_negotiation
property_scheduling >> dim_p
property_scheduling >> dim_proposal
property_scheduling >> dim_booking
property_scheduling >> dim_visit

dim_contract >> fact_property_scheduling
dim_negotiation >> fact_property_scheduling
dim_p >> fact_property_scheduling
dim_proposal >> fact_property_scheduling
dim_booking >> fact_property_scheduling
dim_visit >> fact_property_scheduling
