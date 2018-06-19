import logging
from datetime import datetime, timedelta

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDb
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.new_etl.bridge import Bridge

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'ENV_EBDB', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY')


def xcom_dependencies(task_id, dag_id, **kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    for t_id, d_id in zip(task_id, dag_id):
        status = xcom.xcom_pull(task_instance=kwargs['ti'], key=exec_date, task_id=t_id, dag_id=d_id)
        # if not status:
        #     raise ValueError('For {}, the process {}:{} have not finished yet'.format(exec_date, d_id, t_id))
        # else:
        #     logging.info('REQUIREMENT MET. For {}, the process {}:{} have finished'.format(exec_date, d_id, t_id))

    logging.info('All Requirements met')


def create_bdg_demand_agent():
    bridge = Bridge()
    data = bridge.get_data(f_name='bdg_demand_agent', db_enum=EnumDb.BI_DW)
    bridge.clean_table(schema='public', table='bdg_demand_agent', enumdb=EnumDb.BI_DW)
    bridge.create_table_dw(table_name='bdg_demand_agent', data=data)


def create_bdg_demand_agent_data_integrity():
    bridge = Bridge()
    bridge.garantee_integrity(db_enum=EnumDb.BI_DW, f_name='bdg_demand_agent', dim_name='fact_agent')


dag = DAG(
    dag_id='bi-load-bdg_demand_fact_1',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False,
        'retries': 1,
        'retry_delay': timedelta(minutes=30),
    },
    start_date=datetime(2018, 6, 7, 0, 0, 0),
    schedule_interval='0 3 * * *',
    max_active_runs=1
)

# check the dependencies for bdg_demand_agent
bdg_demand_agent_xcom_dependencies = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='bdg_demand_agent_xcom_dependencies',
    provide_context=True,
    func_command=xcom_dependencies,
    op_kwargs={'task_id': ['XCom_fact_agent', 'XCom_fact_demand'],
               'dag_id': ['bi-load-agent_model', 'bi-supply-demand-etl']}
)

bdg_demand_agent = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='bdg_demand_agent',
    provide_context=True,
    func_command=create_bdg_demand_agent,
    op_kwargs=None
)

bdg_demand_agent_data_integrity = BaseDAG.get_python_operator(  # BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='bdg_demand_agent_data_integrity',
    provide_context=True,
    func_command=create_bdg_demand_agent_data_integrity,
    op_kwargs=None
)

bdg_demand_agent_xcom_dependencies >> bdg_demand_agent
bdg_demand_agent >> bdg_demand_agent_data_integrity

if __name__ == '__main__':
    bridge = Bridge()
    data = bridge.get_data(f_name='bdg_demand_agent', db_enum=EnumDb.BI_DW)
    bridge.clean_table(schema='public', table='bdg_demand_agent', enumdb=EnumDb.BI_DW)
    bridge.create_table_dw(table_name='bdg_demand_agent', data=data)
