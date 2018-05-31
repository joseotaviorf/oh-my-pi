from datetime import datetime

import dateutil.parser as parser
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDb
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.agents.load_agent_region import Agent_Region

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'ENV_EBDB')


def upd_agent_region(**kwargs):
    exec_date = kwargs['prev_execution_date']
    ar = Agent_Region()
    new_data = ar.get_agent_region(f_name='etl_agent_region_daily', db_enum=EnumDb.QuintoAndar_ebdb, dt=exec_date)
    inserted_data, updated_data = ar.split_new_rows(new_data=new_data, dt=exec_date)
    ar.insert_new_data(inserted_data, 'agent_region_hist')
    ar.update_data(data=updated_data, db='public', table='agent_region_hist', enumdb=EnumDb.BI_ODS, date=exec_date)


dag = DAG(
    dag_id='bi-ebdb-load-agent_region_upd',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 5, 30, 0, 0, 0),
    schedule_interval='@daily',
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
    exec_date = parser.parse('2018-05-28 00:00:00')
    ar = Agent_Region()
    new_data = ar.get_agent_region(f_name='etl_agent_region_daily', db_enum=EnumDb.QuintoAndar_ebdb, dt=exec_date)
    inserted_data, updated_data = ar.split_new_rows(new_data=new_data, dt=exec_date)
    print(inserted_data)
    print(updated_data)
    # ar.insert_new_data(inserted_data, 'agent_region_hist')
    ar.update_data(data=updated_data, db='public', table='agent_region_hist', enumdb=EnumDb.BI_ODS, date=exec_date)
