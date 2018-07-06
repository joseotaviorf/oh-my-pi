import logging
from datetime import datetime, timedelta

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDb
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.new_etl.agents.bridge_demand_agent import Bridge

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'ENV_EBDB', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY')


def xcom_dependencies(task_id, dag_id, **kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    for t_id, d_id in zip(task_id, dag_id):
        status = xcom.xcom_pull(task_instance=kwargs['ti'], key=exec_date, task_id=t_id, dag_id=d_id)
        if not status:
            raise ValueError('For {}, the process {}:{} have not finished yet'.format(exec_date, d_id, t_id))
        else:
            logging.info('REQUIREMENT MET. For {}, the process {}:{} have finished'.format(exec_date, d_id, t_id))

    logging.info('All Requirements met')


def create_bdg_demand_agent():
    bridge = Bridge()
    data = bridge.get_data(f_name='bdg_demand_agent', db_enum=EnumDb.BI_DW)
    bridge.clean_table(schema='public', table='bdg_demand_agent', enumdb=EnumDb.BI_DW)
    bridge.create_table_dw(table_name='bdg_demand_agent', data=data)


def guarantee_data_integrity(**kwargs):
    bridge = Bridge()
    bridge.guarantee_integrity(db_enum=kwargs['db_enum'], schema=kwargs['schema'], f_name=kwargs['f_name'],
                               f_column=kwargs['f_column'], dim_name=kwargs['dim_name'],
                               dim_column=kwargs['dim_column'], type=kwargs['type'])


dag = DAG(
    dag_id='bi-load-bdg_demand_agent',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False,
        'retries': 1,
        'retry_delay': timedelta(minutes=30),
    },
    start_date=datetime(2018, 7, 6, 0, 0, 0),
    schedule_interval='0 9 * * *',
    max_active_runs=1
)

# check the dependencies for bdg_demand_agent
bdg_demand_agent_xcom_dependencies = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='bdg_demand_agent_xcom_dependencies',
    provide_context=True,
    func_command=xcom_dependencies,
    op_kwargs={'task_id': ['XCom_fact_agent', 'XCom_fact_demand'],
               'dag_id': ['bi-load-agent_model', 'bi-supply-demand-etl']}
)

bdg_demand_agent = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='bdg_demand_agent',
    func_command=create_bdg_demand_agent,
    op_kwargs=None
)

data_integrity_bdg_fact_agent = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_bdg_fact_agent',
    func_command=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDb.BI_DW,
               'schema': 'public',
               'f_name': 'bdg_demand_agent',
               'f_column': 'sk_slot_date_agent',
               'dim_name': 'fact_agent',
               'dim_column': 'sk_slot_date_agent',
               'type': 'update'}
)

data_integrity_bdg_dim_date = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_bdg_dim_date',
    func_command=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDb.BI_DW,
               'schema': 'public',
               'f_name': 'bdg_demand_agent',
               'f_column': 'sk_date',
               'dim_name': 'dim_date',
               'dim_column': 'sk_date',
               'type': 'update'}
)

data_integrity_bdg_dim_user = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_bdg_dim_user',
    func_command=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDb.BI_DW,
               'schema': 'public',
               'f_name': 'bdg_demand_agent',
               'f_column': 'sk_agent',
               'dim_name': 'dim_user',
               'dim_column': 'dados_agente_id',
               'type': 'update'}
)

data_integrity_bdg_fact_demand = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_bdg_fact_demand',
    func_command=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDb.BI_DW,
               'schema': 'public',
               'f_name': 'bdg_demand_agent',
               'f_column': 'sk_demand',
               'dim_name': 'fact_demand',
               'dim_column': 'ods_id',
               'type': 'update'}
)

data_integrity_fact_demand_dim_booking = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_fact_demand_dim_booking',
    func_command=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDb.BI_DW,
               'schema': 'public',
               'f_name': 'fact_demand',
               'f_column': 'sk_booking',
               'dim_name': 'dim_booking',
               'dim_column': 'sk_booking',
               'type': 'update'}
)

data_integrity_dim_agentreview_booking = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_dim_agentreview_booking',
    func_command=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDb.BI_DW,
               'schema': 'public',
               'f_name': 'dim_agent_review',
               'f_column': 'sk_booking',
               'dim_name': 'dim_booking',
               'dim_column': 'sk_booking',
               'type': 'delete'}
)

bdg_demand_agent_xcom_dependencies >> bdg_demand_agent
bdg_demand_agent >> data_integrity_bdg_fact_agent
data_integrity_bdg_fact_agent >> data_integrity_bdg_dim_date
data_integrity_bdg_dim_date >> data_integrity_bdg_dim_user
data_integrity_bdg_dim_user >> data_integrity_dim_agentreview_booking
data_integrity_dim_agentreview_booking >> data_integrity_fact_demand_dim_booking
data_integrity_fact_demand_dim_booking >> data_integrity_bdg_fact_demand
