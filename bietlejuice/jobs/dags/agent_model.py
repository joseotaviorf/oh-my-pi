import datetime as dt
import json
from datetime import datetime, date, timedelta

from airflow.models import DAG
from airflow.operators.sensors import S3KeySensor

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.etl.agents.agent_model import Agent

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'DATA_ACC_AWS_ACCESS_KEY_ID',
                                 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
bucket_datalake = env.get_airflow_env_var('bi-datalake-s3-bucket')
GOOGLE_S_A_CREDENTIALS = json.loads(
    env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')


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


def create_fact_agent_allocations(table_name, execution_date, **kwargs):
    ar = Agent(bucket_datalake)
    ar.clean_greater_than_daily_data_in_table(enum=EnumDB.BI_DW,
                                              schema='agent',
                                              dim_name=table_name,
                                              date_column='sk_slot_date',
                                              dt=execution_date)
    ar.create_table_dw(table_name=table_name, append=True, dt=execution_date,
                       schema='agent')
    ar.insert_dummy(table_name=table_name,
                    key_column='sk_slot_date_agent',
                    previous_check=True,
                    schema='agent')


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


dag = DAG(
    dag_id='bi-load-agent_model',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': True
    },
    start_date=datetime(2018, 7, 10, 0, 0, 0),
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

# Creates agent_contract in DW
create_agent_contract_dw = BaseDAG.build_python_operator(
    dag=dag,
    task_id='create_agent_contract_dw',
    python_callable=create_agent_contract_dw,
    op_kwargs=None
)

# Creates fact_agent_daily_allocations in DW
create_fact_agent_daily_allocations = BaseDAG.build_python_operator(
    dag=dag,
    task_id='create_fact_agent_daily_allocations',
    provide_context=True,
    python_callable=create_fact_agent_allocations,
    op_kwargs={
        'table_name': 'fact_agent_daily_allocations'
    }
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

# Creates fact_photographer_daily_allocations in DW
create_fact_photographer_daily_allocations = BaseDAG.build_python_operator(
    dag=dag,
    task_id='create_fact_photographer_daily_allocations',
    provide_context=True,
    python_callable=create_fact_agent_allocations,
    op_kwargs={
        'table_name': 'fact_photographer_daily_allocations'
    }
)

# Creates fact_photographer_hourly_allocations in DW
create_fact_photographer_hourly_allocations = BaseDAG.build_python_operator(
    dag=dag,
    task_id='create_fact_photographer_hourly_allocations',
    provide_context=True,
    python_callable=create_fact_agent_allocations,
    op_kwargs={
        'table_name': 'fact_photographer_hourly_allocations'
    }
)

# Creates dim_agent_review in ODS
create_dim_agent_review = BaseDAG.build_python_operator(
    dag=dag,
    task_id='create_dim_agent_review',
    provide_context=True,
    python_callable=create_dim_agent_review,
    op_kwargs=None
)

# Moves dim_agent_review from ODS to DW
load_dim_agent_review_dw = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_dim_agent_review_dw',
    python_callable=load_dim_agent_review_dw,
    op_kwargs=None
)

# Creates push xcom
xcom_fact_agent_daily_allocations = BaseDAG.build_python_operator(
    dag=dag,
    task_id='XCom_fact_agent_daily_allocations',
    provide_context=True,
    python_callable=xcom_fact_agent_daily_allocations
)

# Get EBDB data of Agent_Region per day and updates into ODS
update_agent_region_ods = BaseDAG.build_python_operator(
    dag=dag,
    task_id='update_agent_region_ods',
    provide_context=True,
    python_callable=upd_agent_region,
    op_kwargs=None
)

last_dep_execution_date = str(date.today() - timedelta(days=1))
enrich_ebdb_agents_dep = S3KeySensor(
    task_id="enrich_ebdb_agents_dep",
    poke_interval=3*60,
    timeout=2*60*60,
    aws_conn_id="aws_prod_data",
    bucket_name='5a-datalake-prod',
    bucket_key="dags_execution_logs/{execution_date}/{dependency_dag}.SUCCESS".format(execution_date=last_dep_execution_date, dependency_dag='bietlejuice.enrich_ebdb_agents'),
    dag=dag
)

enrich_ebdb_agents_dep >> update_agent_region_ods
enrich_ebdb_agents_dep >> create_dim_agent_review
enrich_ebdb_agents_dep >> create_agent_contract_dw

update_agent_region_ods >> group_agent_region_ods >> load_group_agent_region_dw >> create_dim_agent_region_dw
create_dim_agent_region_dw.set_downstream(
    [create_fact_photographer_daily_allocations, create_fact_agent_daily_allocations,
     create_fact_agent_hourly_allocations,
     create_fact_photographer_hourly_allocations])
create_agent_contract_dw.set_downstream(
    [create_fact_photographer_daily_allocations, create_fact_agent_daily_allocations,
     create_fact_agent_hourly_allocations,
     create_fact_photographer_hourly_allocations]
)
create_fact_agent_daily_allocations >> xcom_fact_agent_daily_allocations
create_dim_agent_review >> load_dim_agent_review_dw
