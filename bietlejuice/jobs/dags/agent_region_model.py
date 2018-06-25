import datetime as dt
from datetime import datetime

import dateutil.parser as parser
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDb
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.new_etl.agents.load_agent_model import Agent_Region

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'ENV_EBDB', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY')


def group_agent_region(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent_Region()
    ar.clean_daily_data_in_table(enum=EnumDb.BI_ODS, schema='public', dim_name='agent_region_group', date_column='dt',
                                 dt=exec_date, format='YYYY-MM-DD')
    group_data = ar.get_group_regions(f_name='agent_region_group', db_enum=EnumDb.BI_ODS, dt=exec_date)
    ar.move_data_to_ods(data=group_data, table_name='agent_region_group')


def load_group_agent_region_dw(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent_Region()
    ar.move_table_to_dw(table_s='agent_region_group', table_d='staging.agent_region_group')


def create_dim_agent_region_dw(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent_Region()
    ar.clean_agent_dim(schema='public', table='dim_agent_region', enumdb=EnumDb.BI_DW)
    ar.create_dim_or_fact_dw(dim_name='dim_agent_region', append=False)


def create_fact_agent(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent_Region()
    ar.clean_daily_data_in_table(enum=EnumDb.BI_DW, schema='public', dim_name='fact_agent', date_column='sk_slot_date',
                                 dt=exec_date, format='YYYYMMDD')
    ar.create_dim_or_fact_dw(dim_name='fact_agent', append=True, dt=exec_date)
    ar.insert_dummy(table_name='fact_agent', key_column='sk_slot_date_agent')


def create_dim_agent_review(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent_Region()
    ar.clean_agent_dim(schema='public', table='agent_review', enumdb=EnumDb.BI_ODS)
    rev_data = ar.get_agent_reviews(f_name='agent_review', db_enum=EnumDb.QuintoAndar_ebdb, exec_dt=exec_date)
    ar.move_data_to_ods(data=rev_data, table_name='agent_review')


def load_dim_agent_review_dw(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent_Region()
    ar.clean_agent_dim(schema='public', table='dim_agent_review', enumdb=EnumDb.BI_DW)
    ar.move_table_to_dw(table_s='vw_dim_agent_review', table_d='public.dim_agent_review')
    ar.insert_dummy(table_name='dim_agent_review', key_column='sk_agentreview, sk_booking', value='-1,-1')


def xcom_fact_agent(**kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    xcom.xcom_push(kwargs['ti'], exec_date)


def upd_agent_region(**kwargs):
    exec_date = kwargs['execution_date']
    exec_date_max = exec_date + dt.timedelta(days=1)
    ar = Agent_Region()

    ar.clean_daily_data_in_table(enum=EnumDb.BI_ODS, schema='public', dim_name='agent_region_hist',
                                 date_column='dt_start', dt=exec_date, format='YYYY-MM-DD')

    ar.reprocess_old_records(exec_dt=exec_date)

    new_data = ar.get_agent_region(f_name='etl_agent_region_daily', db_enum=EnumDb.QuintoAndar_ebdb, dt=exec_date,
                                   dtmax=exec_date_max)
    inserted_data, updated_data = ar.split_new_rows(new_data=new_data, dt=exec_date)
    ar.insert_new_data(inserted_data, 'agent_region_hist')
    ar.update_data(data=updated_data, db='public', table='agent_region_hist', enumdb=EnumDb.BI_ODS, date=exec_date)


dag = DAG(
    dag_id='bi-load-agent_model',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': True
    },
    start_date=datetime(2018, 1, 1, 0, 0, 0),
    schedule_interval='0 2 * * *',
    max_active_runs=1
)

# Get ODS data of Agent_Region per day and groups into ODS
group_agent_region_ods = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='group_agent_region_ods',
    provide_context=True,
    func_command=group_agent_region,
    op_kwargs=None
)

# Get ODS grouped data to DW
load_group_agent_region_dw = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='load_group_agent_region_dw',
    provide_context=True,
    func_command=load_group_agent_region_dw,
    op_kwargs=None
)

# Creates dim_agent_region in DW
create_dim_agent_region_dw = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='create_dim_agent_region_dw',
    provide_context=True,
    func_command=create_dim_agent_region_dw,
    op_kwargs=None
)

# Creates dim_agent_region in DW
create_fact_agent = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='create_fact_agent',
    provide_context=True,
    func_command=create_fact_agent,
    op_kwargs=None
)

# Creates dim_agent_review in ODS
create_dim_agent_review = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='create_dim_agent_review',
    provide_context=True,
    func_command=create_dim_agent_review,
    op_kwargs=None
)

# Moves dim_agent_review from ODS to DW
load_dim_agent_review_dw = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='load_dim_agent_review_dw',
    provide_context=True,
    func_command=load_dim_agent_review_dw,
    op_kwargs=None
)

# Creates push xcom
xcom_fact_agent = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='XCom_fact_agent',
    provide_context=True,
    func_command=xcom_fact_agent
)

# Get EBDB data of Agent_Region per day and updates into ODS
update_agent_region_ods = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
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

if __name__ == '__main__':
    exec_date = parser.parse('2018-06-25 00:00:00')
    # ar = Agent_Region()
    # group_data = ar.get_group_regions(f_name='agent_region_group', db_enum=EnumDb.BI_ODS, dt=exec_date)
    # ar.move_data_to_ods(data=group_data, table_name='agent_region_group')
    ar = Agent_Region()

    ar.insert_dummy(table_name='fact_agent', key_column='sk_slot_date_agent')
