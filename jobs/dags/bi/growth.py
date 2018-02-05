from datetime import datetime, timedelta
from jobs.base.base_etl import BaseETL, EnumDb
from jobs.dags.util import environment as env
from airflow.models import DAG
from airflow.operators.quintoandar import QuintoAndarPythonOperator
import os

dir_path = os.path.dirname(os.path.realpath(__file__))
GROWTH_QUERIES_DIR = os.path.join(dir_path, '../../../db/3.dw/public/queries/growth')
env.set_airflow_var_to_local_env('BI_DW', 'EBDB')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')


def materialize_growth_measure_table_query(dim_name, query_path, suffix_path):
    # read query and suffix and concatenate
    query_file = '{}/{}.sql'.format(GROWTH_QUERIES_DIR, query_path)
    suffix_file = '{}/{}.sql'.format(GROWTH_QUERIES_DIR, suffix_path)

    with open(query_file) as f:
        query = f.read()
    with open(suffix_file) as f:
        suffix = f.read()
    query += suffix

    BaseETL.execute_command(
        command='drop table if exists growth.{}'.format(dim_name),
        commit=True,
        db_enum=EnumDb.BI_DW
    )

    BaseETL.execute_command(
        command=query,
        commit=True,
        db_enum=EnumDb.BI_DW
    )


def load_fact_growth(query_path):

    query_file = '{}/{}.sql'.format(GROWTH_QUERIES_DIR, query_path)

    BaseETL.execute_command(
        command='drop table if exists growth.fact_growth',
        commit=True,
        db_enum=EnumDb.BI_DW
    )

    BaseETL.execute_file_query(
        filename=query_file,
        commit=True,
        db_enum=EnumDb.BI_DW
    )

# create DAG definition
dag = DAG(
    dag_id='bi-growth',
    description='ETL Pipeline for creating Growth Model inside the DW',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 4, 0, 0, 0),
    schedule_interval=env.convert_to_utc_schedule('0 3 * * *'),
    max_active_runs=1
)

# Supply Measures
leads = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_leads',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'leads', 'query_path': 'supply/leads',  'suffix_path': 'suffix_base'}
)
new_listings = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_new_listings',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'new_listings', 'query_path': 'supply/new_listings',  'suffix_path': 'suffix_base'}
)
opportunities = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_opportunities',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'opportunities', 'query_path': 'supply/opportunities',  'suffix_path': 'suffix_base'}
)
prospects = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_prospects',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'prospects', 'query_path': 'supply/prospects',  'suffix_path': 'suffix_base'}
)
qualifieds = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_qualifieds',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'qualifieds', 'query_path': 'supply/qualifieds',  'suffix_path': 'suffix_base'}
)

# Demand Measures
approved_by_insurer = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_approved_by_insurer',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'approved_by_insurer', 'query_path': 'demand/approved_by_insurer',
               'suffix_path': 'suffix_base'}
)
documentation_sent = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_documentation_sent',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'documentation_sent', 'query_path': 'demand/documentation_sent',
               'suffix_path': 'suffix_base'}
)
offerers = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_offerers',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'offerers', 'query_path': 'demand/offerers',  'suffix_path': 'suffix_base'}
)
offerers_approved = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_offerers_approved',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'offerers_approved', 'query_path': 'demand/offerers_approved',  'suffix_path': 'suffix_base'}
)
offerers_sent_doc = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_offerers_sent_doc',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'offerers_sent_doc', 'query_path': 'demand/offerers_sent_doc',  'suffix_path': 'suffix_base'}
)
offers_approved = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_offers_approved',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'offers_approved', 'query_path': 'demand/offers_approved',  'suffix_path': 'suffix_base'}
)
offers_submitted = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_offers_submitted',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'offers_submitted', 'query_path': 'demand/offers_submitted',  'suffix_path': 'suffix_base'}
)
tenant_prospects = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_tenant_prospects',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'tenant_prospects', 'query_path': 'demand/tenant_prospects',  'suffix_path': 'suffix_base'}
)
tenants = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_tenants',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'tenants', 'query_path': 'demand/tenants',  'suffix_path': 'suffix_base'}
)
visitors = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_visitors',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'visitors', 'query_path': 'demand/visitors',  'suffix_path': 'suffix_base'}
)
visits_booked = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_visits_booked',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'visits_booked', 'query_path': 'demand/visits_booked',  'suffix_path': 'suffix_base'}
)
visits_completed = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_visits_completed',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'visits_completed', 'query_path': 'demand/visits_completed',  'suffix_path': 'suffix_base'}
)

# Closing Measures
ongoing_contracts = QuintoAndarPythonOperator(
    dag=dag,
    task_id='extract_ongoing_contracts',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_growth_measure_table_query,
    op_kwargs={'dim_name': 'ongoing_contracts', 'query_path': 'closing/ongoing_contracts',  'suffix_path': 'suffix_base'}
)

# Top-of-Funnel Measures
# active_users = PythonOperator(
#     dag=dag,
#     task_id='extract_ongoing_contracts',
#     execution_timeout=timedelta(hours=3),
#     python_callable=materialize_growth_measure_table_query,
#     op_kwargs={'dim_name': 'active_users', 'query_path': 'demand/active_users',  'suffix_path': 'suffix_base'}
# )

fact_growth = QuintoAndarPythonOperator(
    dag=dag,
    task_id='load_fact_growth',
    execution_timeout=timedelta(hours=3),
    python_callable=load_fact_growth,
    op_kwargs={'query_path': 'fact_growth'}
)

leads >> fact_growth
new_listings >> fact_growth
opportunities >> fact_growth
prospects >> fact_growth
qualifieds >> fact_growth

approved_by_insurer >> fact_growth
documentation_sent >> fact_growth
offerers >> fact_growth
offerers_approved >> fact_growth
offerers_sent_doc >> fact_growth
offers_approved >> fact_growth
offers_submitted >> fact_growth
tenant_prospects >> fact_growth
tenants >> fact_growth
visitors >> fact_growth
visits_booked >> fact_growth
visits_completed >> fact_growth

ongoing_contracts >> fact_growth
