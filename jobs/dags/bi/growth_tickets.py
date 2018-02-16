from datetime import datetime, timedelta
from jobs.base.base_etl import BaseETL, EnumDb
from jobs.dags.util import environment as env
from airflow.models import DAG
from airflow.operators.quintoandar import QuintoAndarPythonOperator
from jobs.new_etl.dim_utils import load_dim_from_ods_to_dw
import os

dir_path = os.path.dirname(os.path.realpath(__file__))
STAGING_QUERIES_DIR = os.path.join(dir_path, '../../../db/3.dw/growth/staging/queries')
env.set_airflow_var_to_local_env(
    'BI_DW',
    'BI_ODS',
    'AWS_ACCESS_KEY_ID',
    'AWS_SECRET_ACCESS_KEY',
    'AWS_DEFAULT_REGION'
)
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')


def materialize_table_query_dw(dim_name, query_dir, filename=None):
    # read query and suffix and concatenate
    if filename is None:
        filename = dim_name
    query_file = '{}/{}.sql'.format(query_dir, filename)
    with open(query_file) as f:
        query = f.read()

    BaseETL.execute_command(
        command='drop table if exists growth_staging.{}'.format(dim_name),
        commit=True,
        db_enum=EnumDb.BI_DW
    )

    BaseETL.execute_command(
        command=query,
        commit=True,
        db_enum=EnumDb.BI_DW
    )


# TODO: Implement this when Growth Model structure is finished
def load_ticket_growth_data():
    # Select Grouped categories by Date and insert Counts in Growth Model
    pass

# create DAG definition
dag = DAG(
    dag_id='bi-growth-tickets',
    description='ETL Pipeline for collecting post contract tickets, tasks, calls and chat data to Growth Model',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 13, 0, 0, 0),
    schedule_interval=env.convert_to_utc_schedule('0 3 * * *'),
    max_active_runs=1
)

tickets_whats = QuintoAndarPythonOperator(
    dag=dag,
    task_id='etl_tickets_and_whatsapp',
    execution_timeout=timedelta(hours=3),
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'post_contract_tickets_and_whatsapp', 'bucket': bucket, 'insert_dummy': False,
               'schema_source': 'zendesk', 'schema_dest': 'growth_staging'}
)

ticket_res_time = QuintoAndarPythonOperator(
    dag=dag,
    task_id='etl_ticket_res_time',
    execution_timeout=timedelta(hours=3),
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'post_contract_ticket_full_resolution_time', 'bucket': bucket, 'insert_dummy': False,
               'schema_source': 'zendesk', 'schema_dest': 'growth_staging'}
)

ticket_base = QuintoAndarPythonOperator(
    dag=dag,
    task_id='etl_ticket_base_data',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_table_query_dw,
    op_kwargs={'dim_name': 'post_contract_ticket_base', 'query_dir': STAGING_QUERIES_DIR,
               'filename': 'load_post_contract_ticket_base'}
)

ticket_growth = QuintoAndarPythonOperator(
    dag=dag,
    task_id='etl_ticket_growth_data',
    execution_timeout=timedelta(hours=3),
    python_callable=load_ticket_growth_data
)

tickets_whats >> ticket_base
ticket_base >> ticket_growth
ticket_res_time >> ticket_growth