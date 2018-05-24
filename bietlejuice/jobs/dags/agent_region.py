from datetime import datetime

import dateutil.parser as parser
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.agents.load_agent_region import Agent_Region

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'ENV_EBDB')


def load_agent_region(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent_Region()
    data = ar.get_agent_region()
    ar.move_data_to_ods(data, 'agent_region_hist')


dag = DAG(
    dag_id='bi-ebdb-load-agent_region',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 5, 23, 0, 0, 0),
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

if __name__ == '__main__':
    execution_date = parser.parse('2018-04-06 00:00:00')
    ar = Agent_Region()
    data = ar.get_agent_region()
    ar.move_data_to_ods(data, 'agent_region_hist')
    print(data)
