from datetime import datetime
import json
from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from jobs.dags.util import environment as env
from qa_python_utils.aws.athena import AthenaClient
from jobs.new_etl.business_dim_etl import BusinessDimensionETL
from jobs.new_etl.marketing_dim_etl import MarketingDimensionETL
from jobs.new_etl.dim_utils import extract_query_dim_from_ebdb_to_ods, extract_table_dim_from_ebdb_to_ods, \
    load_dim_from_ods_to_dw, load_athena_query_to_ods, load_marketing_costs

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
criteo_config = env.get_airflow_env_var('criteo')
google_config = env.get_airflow_env_var('ADWORDS_KEY')
facebook_config = env.get_airflow_env_var('FACEBOOK_KEY')
mkt_configs = dict()
mkt_configs['criteo'] = json.loads(criteo_config)
mkt_configs['facebook'] = json.loads(facebook_config)
mkt_configs['google'] = google_config
athena = AthenaClient(bucket)
now = datetime.now()

biz_etl = BusinessDimensionETL(bucket, now)
mkt_etl = MarketingDimensionETL(bucket, mkt_configs)

# create DAG definition
dag = DAG(
    dag_id='bi-supply-potential-listings',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 1, 10, 0, 0, 0),
    schedule_interval=env.convert_to_utc_schedule('0 3 * * *'),
    max_active_runs=1
)

# Lead Dimension
lead = PythonOperator(
    dag=dag,
    task_id='ODS_lead',
    python_callable=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'lead', 'bucket': bucket, 'command': 'call ebdb.list_lead();'}
)
dim_lead = PythonOperator(
    dag=dag,
    task_id='DW_dim_lead',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_lead', 'bucket': bucket}
)

# Contacts and Prospects Dimension
contacts_and_prospects = PythonOperator(
    dag=dag,
    task_id='ODS_contacts_and_prospects',
    python_callable=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'contacts_and_prospects',  'bucket': bucket, 'command': 'call ebdb.list_contacts_and_prospects();'}
)
dim_contacts_and_prospects = PythonOperator(
    dag=dag,
    task_id='DW_contacts_and_prospects',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_contacts_and_prospects', 'bucket': bucket}
)

# Property Dimension
imovel = PythonOperator(
    dag=dag,
    task_id='ODS_imovel',
    python_callable=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'property',  'bucket': bucket, 'command': 'call ebdb.list_imovel();', 'table_name': 'imovel'}
)
dim_property = PythonOperator(
    dag=dag,
    task_id='DW_dim_property',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_property', 'bucket': bucket}
)
dim_status_over_period = PythonOperator(
    dag=dag,
    task_id='DW_dim_property_status_over',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_property_status_over_period', 'bucket': bucket, 'insert_dummy': False}
)

# Region Dimension
region = PythonOperator(
    dag=dag,
    task_id='ODS_region',
    python_callable=extract_table_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'region',  'bucket': bucket, 'table_name': 'MapRegiao', 'add_timestamp': True, 'copy_to_clean': False}
)
dim_region = PythonOperator(
    dag=dag,
    task_id='DW_dim_region',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_region', 'bucket': bucket,
               'post_command': "update dim_region set dt_timestamp = '{}' where sk_region = -1;".format(
                   now.strftime('%Y-%m-%d'))}
)

# User Dimension
usuario = PythonOperator(
    dag=dag,
    task_id='ODS_usuario',
    python_callable=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'user', 'table_name': 'usuario', 'bucket': bucket, 'command': 'call ebdb.list_usuario();'}
)
dim_user = PythonOperator(
    dag=dag,
    task_id='DW_dim_user',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_user', 'bucket': bucket}
)

# Marketing Attribution Dimension
mkt = PythonOperator(
    dag=dag,
    task_id='ODS_marketing_attribution',
    python_callable=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'marketing_attribution',  'bucket': bucket, 'command': 'call ebdb.list_marketing_attribution();'}
)
dim_marketing_attribution = PythonOperator(
    dag=dag,
    task_id='DW_dim_marketing_attribution',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_marketing_attribution', 'bucket': bucket}
)

# Potential Listings Fact Table
listings = PythonOperator(
    dag=dag,
    task_id='ODS_Potential_Listings',
    python_callable=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'potential_listings',  'bucket': bucket, 'command': 'call ebdb.list_potential_listings(null);'}
)
fact_supply_cac = PythonOperator(
    dag=dag,
    task_id='DW_Fact_Supply_CAC',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'fact_supply_potential_listings', 'bucket': bucket, 'insert_dummy': False}
)

# Marketing Ads Costs Dimension
mkt_fb_costs = PythonOperator(
    dag=dag,
    task_id='ODS_marketing_facebook_ads_costs',
    python_callable=load_marketing_costs,
    op_kwargs={'dim_name': 'facebook', 'bucket': bucket, 'mkt_configs': mkt_configs}
)
mkt_g_costs = PythonOperator(
    dag=dag,
    task_id='ODS_marketing_google_adwords_costs',
    python_callable=load_marketing_costs,
    op_kwargs={'dim_name': 'google', 'bucket': bucket, 'mkt_configs': mkt_configs}
)
mkt_crit_costs = PythonOperator(
    dag=dag,
    task_id='ODS_marketing_criteo_costs',
    python_callable=load_marketing_costs,
    op_kwargs={'dim_name': 'criteo', 'bucket': bucket, 'mkt_configs': mkt_configs}
)

# Affiliate Payments Dimension
affiliate_payments = PythonOperator(
    dag=dag,
    task_id='ODS_affiliate_payments',
    python_callable=load_athena_query_to_ods,
    op_kwargs={'dim_name': 'affiliate_payments', 'bucket': bucket, 'fname': 'affiliate_payments'}
)

# Photo Job
photo_job = PythonOperator(
    dag=dag,
    task_id='ODS_photo_job',
    python_callable=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'photo_job',  'bucket': bucket, 'command': 'call ebdb.list_photo_job();'}
)
dim_photo_job = PythonOperator(
    dag=dag,
    task_id='DW_dim_photo_job',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'dim_photo_job', 'bucket': bucket}
)

# flow
contacts_and_prospects >> dim_contacts_and_prospects
lead >> dim_lead
imovel >> dim_property
affiliate_payments >> dim_property
region >> dim_region
usuario >> dim_user
photo_job >> dim_photo_job
mkt >> dim_marketing_attribution
mkt_fb_costs >> dim_marketing_attribution
mkt_g_costs >> dim_marketing_attribution
mkt_crit_costs >> dim_marketing_attribution

dim_lead >> fact_supply_cac
dim_region >> fact_supply_cac
dim_user >> fact_supply_cac
dim_marketing_attribution >> fact_supply_cac
dim_contacts_and_prospects >> fact_supply_cac
dim_photo_job >> fact_supply_cac

dim_property >> dim_status_over_period
dim_status_over_period >> fact_supply_cac

listings >> fact_supply_cac
