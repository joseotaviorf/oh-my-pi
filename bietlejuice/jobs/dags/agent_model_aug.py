import datetime as dt
import json
from datetime import datetime

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.etl.agents.agent_model import Agent

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB')
bucket_datalake = env.get_airflow_env_var('bi-datalake-s3-bucket')
GOOGLE_S_A_CREDENTIALS = json.loads(
    env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')
GOOGLE_SHEETS_FILES = json.loads(env.get_airflow_env_var('GOOGLE_SHEETS_FILES'))


def group_agent_region(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent(bucket_datalake)
    ar.clean_daily_data_in_table(enum=EnumDB.BI_ODS,
                                 schema='public',
                                 dim_name='agent_region_group',
                                 date_column='dt',
                                 dt=exec_date,
                                 format='YYYY-MM-DD')
    group_data = ar.get_agent_data(table_name='agent_region_group',
                                   db_enum=EnumDB.BI_ODS,
                                   dt=exec_date)
    ar.move_data_to_destination(data=group_data,
                                table_name='agent_region_group')


def load_group_agent_region_dw():
    BaseETL.move_table_to_dw('agent_region_group',
                             EnumDB.BI_ODS,
                             EnumDB.BI_DW,
                             table_name_dest='staging.agent_region_group',
                             append=False)


def create_dim_agent_region_dw():
    ar = Agent(bucket_datalake)
    ar.truncate_table(schema='public',
                      table='dim_agent_region',
                      enumdb=EnumDB.BI_DW)
    ar.create_table_dw(table_name='dim_agent_region', append=False)
    ar.insert_dummy(table_name='dim_agent_region',
                    key_column='sk_agent_region',
                    previous_check=True)


def create_agent_contract_dw():
    ar = Agent(bucket_datalake)
    ar.truncate_table(schema='agent',
                      table='agent_contract',
                      enumdb=EnumDB.BI_DW)
    data = ar.get_agent_data(table_name='agent_contract',
                             db_enum=EnumDB.QuintoAndar_ebdb)
    ar.move_data_to_destination(data=data,
                                table_name='agent_contract',
                                enumdb=EnumDB.BI_DW,
                                bucket='clean',
                                append=False,
                                schema='agent')


def create_dim_agent_contract_type():
    ar = Agent(bucket_datalake)
    ar.move_sheets_data_to_datalake(
        google_s_a_credentials=GOOGLE_S_A_CREDENTIALS,
        google_api_scope=GOOGLE_API_SCOPE,
        google_sheets_files=GOOGLE_SHEETS_FILES,
        filename='[Agent] Contracts_Hours',
        path='agent_contract_type')
    table = ar.get_agent_data(table_name='dim_agent_contract_type',
                              db_enum=EnumDB.BI_DW,
                              schema='agent')
    ar.move_data_to_destination(data=table,
                                table_name='dim_agent_contract_type',
                                enumdb=EnumDB.BI_DW,
                                append=False,
                                schema='agent',
                                decode=False)
    ar.insert_dummy(table_name='dim_agent_contract_type',
                    key_column='sk_agent_contract_type', schema='agent')


def create_fact_agent_allocations(table_name, execution_date, **kwargs):
    ar = Agent(bucket_datalake)
    ar.clean_greater_than_daily_data_in_table(enum=EnumDB.BI_DW,
                                              schema='agent',
                                              dim_name=table_name,
                                              date_column='sk_slot_date',
                                              dt=execution_date)
    ar.create_table_dw(table_name=table_name, append=True, dt=execution_date, schema='agent')
    ar.insert_dummy(table_name=table_name,
                    key_column='sk_slot_date_agent',
                    previous_check=True,
                    schema='agent')


def create_fact_photographer(**kwargs):
    exec_date = kwargs['execution_date']
    table_name = 'fact_photographer'
    ar = Agent(bucket_datalake)
    ar.clean_greater_than_daily_data_in_table(enum=EnumDB.BI_DW,
                                              schema='public',
                                              dim_name=table_name,
                                              date_column='sk_slot_date',
                                              dt=exec_date)
    ar.create_table_dw(table_name=table_name, append=True, dt=exec_date)


def create_dim_agent_review(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent(bucket_datalake)
    ar.truncate_table(schema='public',
                      table='agent_review',
                      enumdb=EnumDB.BI_ODS)
    rev_data = ar.get_agent_data(table_name='agent_review',
                                 db_enum=EnumDB.QuintoAndar_ebdb,
                                 dt=exec_date)
    ar.move_data_to_destination(data=rev_data, table_name='agent_review')


def load_dim_agent_review_dw():
    ar = Agent(bucket_datalake)
    ar.truncate_table(schema='public',
                      table='dim_agent_review',
                      enumdb=EnumDB.BI_DW)
    BaseETL.move_table_to_dw('vw_dim_agent_review',
                             EnumDB.BI_ODS,
                             EnumDB.BI_DW,
                             table_name_dest='public.dim_agent_review',
                             append=False)
    ar.insert_dummy(table_name='dim_agent_review',
                    key_column='sk_agentreview, sk_booking',
                    value='-1,-1')


def xcom_fact_agent_daily_allocations(**kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    xcom.xcom_push(kwargs['ti'], exec_date)


def upd_agent_region(**kwargs):
    exec_date = kwargs['execution_date']
    exec_date_max = exec_date + dt.timedelta(days=1)
    ar = Agent(bucket_datalake)

    ar.clean_daily_data_in_table(enum=EnumDB.BI_ODS,
                                 schema='public',
                                 dim_name='agent_region_hist',
                                 date_column='dt_start',
                                 dt=exec_date,
                                 format='YYYY-MM-DD')

    ar.reprocess_old_records(exec_dt=exec_date)

    new_data = ar.get_agent_data(table_name='etl_agent_region_daily',
                                 db_enum=EnumDB.QuintoAndar_ebdb,
                                 dt=exec_date,
                                 dtmax=exec_date_max)
    inserted_data, updated_data = ar.split_new_rows(new_data=new_data,
                                                    dt=exec_date)
    ar.move_data_to_destination(data=inserted_data,
                                table_name='agent_region_hist')
    ar.update_data(data=updated_data,
                   db='public',
                   table='agent_region_hist',
                   enumdb=EnumDB.BI_ODS,
                   date=exec_date)


def create_agent_status_history():
    table_name = 'agent_status_history'
    ar = Agent(bucket_datalake)
    rev_data = ar.get_datalake_data_from_filequery(file_name=table_name)
    ar.move_data_to_destination(data=rev_data, enumdb=EnumDB.BI_DW,
                                table_name=table_name, append=False, schema='agent')


dag = DAG(
    dag_id='bi-load-agent_model-AUG',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': True
    },
    start_date=datetime(2019, 8, 1, 0, 0, 0),
    end_date=datetime(2019, 9, 1, 0, 0, 0),
    schedule_interval='0 8 * * *',
    max_active_runs=1,
    orientation='TB'
)

# Get ODS data of Agent_Region per day and groups into ODS
group_agent_region_ods = BaseDAG.build_python_operator(
    dag=dag,
    task_id='group_agent_region_ods',
    provide_context=True,
    python_callable=group_agent_region,
    op_kwargs=None
)

# Get ODS grouped data to DW
load_group_agent_region_dw = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_group_agent_region_dw',
    python_callable=load_group_agent_region_dw,
    op_kwargs=None
)

# Creates dim_agent_region in DW
create_dim_agent_region_dw = BaseDAG.build_python_operator(
    dag=dag,
    task_id='create_dim_agent_region_dw',
    python_callable=create_dim_agent_region_dw,
    op_kwargs=None
)


# Creates fact_agent_hourly_allocations in DW
create_fact_agent_hourly_allocations = BaseDAG.build_python_operator(
    dag=dag,
    task_id='create_fact_agent_hourly_allocations',
    provide_context=True,
    python_callable=create_fact_agent_allocations,
    op_kwargs={
        'table_name': 'fact_agent_hourly_allocations'
    }
)

# Get EBDB data of Agent_Region per day and updates into ODS
update_agent_region_ods = BaseDAG.build_python_operator(
    dag=dag,
    task_id='update_agent_region_ods',
    provide_context=True,
    python_callable=upd_agent_region,
    op_kwargs=None
)

agent_status_history_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='agent_status_history_task',
    python_callable=create_agent_status_history
)

update_agent_region_ods >> group_agent_region_ods
group_agent_region_ods >> load_group_agent_region_dw
load_group_agent_region_dw >> create_dim_agent_region_dw
create_dim_agent_region_dw.set_downstream(
    [create_fact_agent_hourly_allocations])
agent_status_history_task.set_downstream(
    [create_fact_agent_hourly_allocations])
