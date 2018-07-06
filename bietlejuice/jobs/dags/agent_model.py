import datetime as dt
from datetime import datetime

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDb, BaseETL
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.new_etl.agents.load_agent_model import Agent

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'ENV_EBDB', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY')


def group_agent_region(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent()
    ar.clean_daily_data_in_table(enum=EnumDb.BI_ODS, schema='public', dim_name='agent_region_group', date_column='dt',
                                 dt=exec_date, format='YYYY-MM-DD')
    group_data = ar.get_agent_data(f_name='agent_region_group', db_enum=EnumDb.BI_ODS, dt=exec_date)
    ar.move_data_to_destination(data=group_data, table_name='agent_region_group')


def load_group_agent_region_dw():
    BaseETL.move_table_to_dw('agent_region_group', EnumDb.BI_ODS, EnumDb.BI_DW,
                             table_name_dest='staging.agent_region_group', append=False)


def create_dim_agent_region_dw():
    ar = Agent()
    ar.truncate_table(schema='public', table='dim_agent_region', enumdb=EnumDb.BI_DW)
    ar.create_dim_or_fact_dw(dim_name='dim_agent_region', append=False)
    ar.insert_dummy(table_name='dim_agent_region', key_column='sk_agentregion', previous_check=True)


def create_fact_agent(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent()
    ar.clean_daily_data_in_table(enum=EnumDb.BI_DW, schema='public', dim_name='fact_agent', date_column='sk_slot_date',
                                 dt=exec_date, format='YYYYMMDD')
    ar.create_dim_or_fact_dw(dim_name='fact_agent', append=True, dt=exec_date)
    ar.insert_dummy(table_name='fact_agent', key_column='sk_slot_date_agent', previous_check=True)


def create_dim_agent_review(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent()
    ar.truncate_table(schema='public', table='agent_review', enumdb=EnumDb.BI_ODS)
    rev_data = ar.get_agent_data(f_name='agent_review', db_enum=EnumDb.QuintoAndar_ebdb, dt=exec_date)
    ar.move_data_to_destination(data=rev_data, table_name='agent_review')


def load_dim_agent_review_dw():
    ar = Agent()
    ar.truncate_table(schema='public', table='dim_agent_review', enumdb=EnumDb.BI_DW)
    BaseETL.move_table_to_dw('vw_dim_agent_review', EnumDb.BI_ODS, EnumDb.BI_DW,
                             table_name_dest='public.dim_agent_review', append=False)
    ar.insert_dummy(table_name='dim_agent_review', key_column='sk_agentreview, sk_booking', value='-1,-1')


def xcom_fact_agent(**kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    xcom.xcom_push(kwargs['ti'], exec_date)


def upd_agent_region(**kwargs):
    exec_date = kwargs['execution_date']
    exec_date_max = exec_date + dt.timedelta(days=1)
    ar = Agent()

    ar.clean_daily_data_in_table(enum=EnumDb.BI_ODS, schema='public', dim_name='agent_region_hist',
                                 date_column='dt_start', dt=exec_date, format='YYYY-MM-DD')

    ar.reprocess_old_records(exec_dt=exec_date)

    new_data = ar.get_agent_data(f_name='etl_agent_region_daily', db_enum=EnumDb.QuintoAndar_ebdb, dt=exec_date,
                                 dtmax=exec_date_max)
    inserted_data, updated_data = ar.split_new_rows(new_data=new_data, dt=exec_date)
    ar.move_data_to_destination(inserted_data, 'agent_region_hist')
    ar.update_data(data=updated_data, db='public', table='agent_region_hist', enumdb=EnumDb.BI_ODS, date=exec_date)


dag = DAG(
    dag_id='bi-load-agent_model',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': True
    },
    start_date=datetime(2018, 7, 6, 0, 0, 0),
    schedule_interval='0 8 * * *',
    max_active_runs=1
)

# Get ODS data of Agent_Region per day and groups into ODS
group_agent_region_ods = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='group_agent_region_ods',
    provide_context=True,
    func_command=group_agent_region,
    op_kwargs=None
)

# Get ODS grouped data to DW
load_group_agent_region_dw = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='load_group_agent_region_dw',
    func_command=load_group_agent_region_dw,
    op_kwargs=None
)

# Creates dim_agent_region in DW
create_dim_agent_region_dw = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='create_dim_agent_region_dw',
    func_command=create_dim_agent_region_dw,
    op_kwargs=None
)

# Creates dim_agent_region in DW
create_fact_agent = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='create_fact_agent',
    provide_context=True,
    func_command=create_fact_agent,
    op_kwargs=None
)

# Creates dim_agent_review in ODS
create_dim_agent_review = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='create_dim_agent_review',
    provide_context=True,
    func_command=create_dim_agent_review,
    op_kwargs=None
)

# Moves dim_agent_review from ODS to DW
load_dim_agent_review_dw = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='load_dim_agent_review_dw',
    func_command=load_dim_agent_review_dw,
    op_kwargs=None
)

# Creates push xcom
xcom_fact_agent = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='XCom_fact_agent',
    provide_context=True,
    func_command=xcom_fact_agent
)

# Get EBDB data of Agent_Region per day and updates into ODS
update_agent_region_ods = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='update_agent_region_ods',
    provide_context=True,
    func_command=upd_agent_region,
    op_kwargs=None
)

update_agent_region_ods >> group_agent_region_ods
group_agent_region_ods >> load_group_agent_region_dw
load_group_agent_region_dw >> create_dim_agent_region_dw
create_dim_agent_region_dw >> create_fact_agent
create_fact_agent >> xcom_fact_agent
create_dim_agent_review >> load_dim_agent_review_dw
