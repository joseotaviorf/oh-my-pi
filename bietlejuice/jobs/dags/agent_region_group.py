from datetime import datetime

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDb
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.agents.load_agent_region import Agent_Region

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'ENV_EBDB', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY')


def group_agent_region(**kwargs):
    exec_date = kwargs['prev_execution_date']
    ar = Agent_Region()
    group_data = ar.get_group_regions(f_name='agent_region_group', db_enum=EnumDb.BI_ODS, dt=exec_date)
    ar.move_data_to_ods(data=group_data, table_name='agent_region_group')


def load_group_agent_region_dw(**kwargs):
    exec_date = kwargs['prev_execution_date']
    ar = Agent_Region()
    ar.move_table_to_dw()


def create_dim_agent_region_dw(**kwargs):
    exec_date = kwargs['prev_execution_date']
    ar = Agent_Region()
    ar.clean_agent_region(schema='public', table='dim_agent_region', enumdb=EnumDb.BI_DW)
    ar.create_dim_dw('dim_agent_region')


def create_fact_agent_availability(**kwargs):
    exec_date = kwargs['prev_execution_date']
    ar = Agent_Region()
    ar.clean_agent_region(schema='public', table='dim_agent_region', enumdb=EnumDb.BI_DW)
    ar.create_dim_dw('dim_agent_region')


dag = DAG(
    dag_id='bi-load-agent_region_group',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 5, 20, 0, 0, 0),
    schedule_interval='@daily',
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
create_fact_agent_availability = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='create_fact_agent_availability',
    provide_context=True,
    func_command=create_fact_agent_availability,
    op_kwargs=None
)

group_agent_region_ods >> load_group_agent_region_dw
load_group_agent_region_dw >> create_dim_agent_region_dw
create_dim_agent_region_dw >> create_fact_agent_availability

if __name__ == '__main__':
    # exec_date = parser.parse('2018-05-28 00:00:00')
    # ar = Agent_Region()
    # group_data = ar.get_group_regions(f_name='agent_region_group', db_enum=EnumDb.BI_ODS, dt=exec_date)
    # ar.move_data_to_ods(data=group_data, table_name='agent_region_group')
    ar = Agent_Region()
    ar.clean_agent_region(schema='public', table='dim_agent_region', enumdb=EnumDb.BI_DW)
    ar.create_dim_dw('dim_agent_region')
