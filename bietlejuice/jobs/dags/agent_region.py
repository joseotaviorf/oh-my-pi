from datetime import datetime

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDb
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.agents.load_agent_model import Agent

env.set_airflow_var_to_local_env('BI_ODS', 'EBDB', 'ENV_EBDB')


def load_agent_region(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent()
    data = ar.get_agent_data(f_name='etl_agent_region', dt=exec_date, db_enum=EnumDb.QuintoAndar_ebdb)
    ar.move_data_to_destination(data, 'agent_region_hist')


def clean_agent_region():
    ar = Agent()
    ar.truncate_table(schema='public', table='agent_region_hist', enumdb=EnumDb.BI_ODS)


dag = DAG(
    dag_id='bi-ebdb-load-agent_region',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 7, 6, 0, 0, 0),
    schedule_interval='@once',
    max_active_runs=1
)

# Get EBDB data of Agent_Region and dumps into ODS
load_agent_region_to_ods = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='load_agent_region_to_ods',
    provide_context=True,
    func_command=load_agent_region,
    op_kwargs=None
)

clean_agent_region_to_ods = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='clean_agent_region_to_ods',
    func_command=clean_agent_region,
    op_kwargs=None
)

clean_agent_region_to_ods >> load_agent_region_to_ods
