from datetime import datetime

import dateutil.parser as parser
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.agents.load_agent_region import Agent_Region

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'ENV_EBDB')


def upd_agent_region(**kwargs):
    exec_date = kwargs['execution_date']
    ar = Agent_Region()
    data = ar.get_agent_region(f_name='etl_agent_region_daily', dt=exec_date)
    ar.move_data_to_ods(data, 'agent_region_hist')


dag = DAG(
    dag_id='bi-ebdb-load-agent_region_upd',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 5, 23, 0, 0, 0),
    schedule_interval='@once',
    max_active_runs=1
)

# Get EBDB data of Agent_Region per day and updates into ODS
update_agent_region_ods = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='update_agent_region_ods',
    provide_context=True,
    func_command=upd_agent_region,
    op_kwargs=None
)

if __name__ == '__main__':
    exec_date = parser.parse('2018-05-24 00:00:00')
    ar = Agent_Region()
    data = ar.get_agent_region(f_name='etl_agent_region_daily', dt=exec_date)
    # ar.move_data_to_ods(data, 'agent_region_hist')
    ar.process_new_rows(data)
    print(data)
