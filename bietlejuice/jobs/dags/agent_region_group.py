from datetime import datetime

import dateutil.parser as parser
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDb
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.agents.load_agent_region import Agent_Region

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'ENV_EBDB')


def group_agent_region(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent_Region()
    group_data = ar.get_group_regions(f_name='agent_region_group', db_enum=EnumDb.BI_ODS, dt=exec_date)
    ar.move_data_to_ods(data=group_data, table_name='agent_region_group')


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

if __name__ == '__main__':
    exec_date = parser.parse('2018-05-28 00:00:00')
    ar = Agent_Region()
    group_data = ar.get_group_regions(f_name='agent_region_group', db_enum=EnumDb.BI_ODS, dt=exec_date)
    ar.move_data_to_ods(data=group_data, table_name='agent_region_group')
