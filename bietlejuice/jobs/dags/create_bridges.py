from datetime import datetime

import dateutil.parser as parser
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDb
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.new_etl.agents.load_agent_region import Agent_Region

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'ENV_EBDB', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY')


def xcom_dependencies(task_id, dag_id, **kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    # xcom.xcom_push(kwargs['ti'], exec_date)
    for t_id, d_id in zip(task_id, dag_id):
        print(t_id, ' ', d_id)
        status = xcom.xcom_pull(task_instance=kwargs['ti'], key=exec_date, task_id=t_id, dag_id=d_id)

        if not status:
            raise ValueError('For {}, the process {}:{} have not finished yet'.format(exec_date, dag_id, task_id))


dag = DAG(
    dag_id='bi-load-bridges',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 6, 1, 0, 0, 0),
    schedule_interval='@hourly',
    max_active_runs=1
)

# check the dependencies for bdg_demand_agent
bdg_demand_agent_xcom_dependencies = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='bdg_demand_agent_xcom_dependencies',
    provide_context=True,
    func_command=xcom_dependencies,
    op_kwargs={'task_id': ['XCom_fact_agent', 'XCom_fact_demand'],
               'dag_id': ['bi-load-agent_region_group', 'bi-supply-demand-etl']}
)

if __name__ == '__main__':
    exec_date = parser.parse('2018-05-28 00:00:00')
    # ar = Agent_Region()
    # group_data = ar.get_group_regions(f_name='agent_region_group', db_enum=EnumDb.BI_ODS, dt=exec_date)
    # ar.move_data_to_ods(data=group_data, table_name='agent_region_group')
    ar = Agent_Region()
    ar.clean_agent_dim(schema='public', table='dim_agent_review', enumdb=EnumDb.BI_DW)
    ar.move_table_to_dw(table_s='vw_dim_agent_review', table_d='public.dim_agent_review')
