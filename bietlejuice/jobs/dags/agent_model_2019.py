import json
from datetime import datetime

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.agents.agent_model import Agent

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB')
bucket_datalake = env.get_airflow_env_var('bi-datalake-s3-bucket')
GOOGLE_S_A_CREDENTIALS = json.loads(
    env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')
GOOGLE_SHEETS_FILES = json.loads(env.get_airflow_env_var('GOOGLE_SHEETS_FILES'))


def create_fact_photographer_hourly_allocations(**kwargs):
    exec_date = kwargs['execution_date']
    table_name = 'fact_photographer_hourly_allocations'
    ar = Agent(bucket_datalake)
    ar.clean_greater_than_daily_data_in_table(enum=EnumDB.BI_DW,
                                              schema='public',
                                              dim_name=table_name,
                                              date_column='sk_slot_date',
                                              dt=exec_date)
    ar.create_table_dw(table_name=table_name, append=True, dt=exec_date)


dag = DAG(
    dag_id='bi-load-agent_model_photographer_2019',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': True
    },
    start_date=datetime(2019, 1, 1, 0, 0, 0),
    schedule_interval='0 8 * * *',
    max_active_runs=1,
    orientation='TB',
    catchup=True
)

# Creates fact_photographer_hourly_allocations in DW
create_fact_photographer_hourly_allocations = BaseDAG.build_python_operator(
    dag=dag,
    task_id='create_fact_photographer_hourly_allocations',
    provide_context=True,
    python_callable=create_fact_photographer_hourly_allocations,
    op_kwargs=None
)
