import logging
from datetime import datetime, timedelta

import bietlejuice.jobs.new_etl.powerbi as powerbi
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.new_etl.agents.bridge_listing_rent_flows_agent import Bridge

PWBI_AUTH = env.get_airflow_env_var('PWBI_AUTH')
PWBI_SCHEMA = env.get_airflow_env_var('PWBI_SCHEMA')
env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB')
bucket_datalake = env.get_airflow_env_var('bi-datalake-s3-bucket')


def xcom_dependencies(task_id, dag_id, **kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    for t_id, d_id in zip(task_id, dag_id):
        status = xcom.xcom_pull(task_instance=kwargs['ti'], key=exec_date, task_id=t_id, dag_id=d_id)
        if not status:
            raise ValueError('For {}, the process {}:{} have not finished yet'.format(exec_date, d_id, t_id))
        else:
            logging.info('REQUIREMENT MET. For {}, the process {}:{} have finished'.format(exec_date, d_id, t_id))

    logging.info('All Requirements met')


def create_bdg_listing_rent_flows_agent():
    bridge = Bridge(bucket_datalake)
    data = bridge.get_data(f_name='bdg_listing_rent_flows_agent', db_enum=EnumDB.BI_DW, schema='public')
    bridge.clean_table(schema='public', table='bdg_listing_rent_flows_agent', enumdb=EnumDB.BI_DW)
    bridge.create_table_dw(table_name='bdg_listing_rent_flows_agent', data=data)


def guarantee_data_integrity(**kwargs):
    bridge = Bridge(bucket_datalake)
    bridge.guarantee_integrity(db_enum=kwargs['db_enum'], schema=kwargs['schema'], f_name=kwargs['f_name'],
                               f_column=kwargs['f_column'], dim_name=kwargs['dim_name'],
                               dim_column=kwargs['dim_column'], type=kwargs['type'])


def refresh_powerbi(**kwargs):
    powerbi_client = powerbi.PowerBIClient(PWBI_AUTH,
                                           PWBI_SCHEMA,
                                           kwargs['workspace_name'],
                                           kwargs['dataset_name'])
    powerbi_client.trigger_refresh()


dag = DAG(
    dag_id='bi-load-bdg_demand_agent',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False,
        'retries': 1,
        'retry_delay': timedelta(minutes=30),
    },
    start_date=datetime(2018, 7, 10, 0, 0, 0),
    schedule_interval='0 9 * * *',
    max_active_runs=1
)

# check the dependencies for bdg_listing_rent_flows_agent
bdg_listing_rent_flows_agent_xcom_dependencies = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='bdg_demand_agent_xcom_dependencies',
    provide_context=True,
    python_callable=xcom_dependencies,
    op_kwargs={'task_id': ['XCom_fact_agent', 'XCom_fact_listing_rent_flows'],
               'dag_id': ['bi-load-agent_model', 'bi-supply-demand-etl']}
)

bdg_listing_rent_flows_agent = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='bdg_demand_agent',
    python_callable=create_bdg_listing_rent_flows_agent,
    op_kwargs=None
)

data_integrity_bdg_fact_agent = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_bdg_fact_agent',
    python_callable=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDB.BI_DW,
               'schema': 'public',
               'f_name': 'bdg_listing_rent_flows_agent',
               'f_column': 'sk_slot_date_agent',
               'dim_name': 'fact_agent',
               'dim_column': 'sk_slot_date_agent',
               'type': 'update'}
)

data_integrity_bdg_dim_date = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_bdg_dim_date',
    python_callable=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDB.BI_DW,
               'schema': 'public',
               'f_name': 'bdg_listing_rent_flows_agent',
               'f_column': 'sk_date',
               'dim_name': 'dim_date',
               'dim_column': 'sk_date',
               'type': 'update'}
)

data_integrity_bdg_dim_user = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_bdg_dim_user',
    python_callable=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDB.BI_DW,
               'schema': 'public',
               'f_name': 'bdg_listing_rent_flows_agent',
               'f_column': 'sk_agent',
               'dim_name': 'dim_user',
               'dim_column': 'dados_agente_id',
               'type': 'update'}
)

data_integrity_bdg_fact_listing_rent_flows = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_bdg_fact_demand',
    python_callable=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDB.BI_DW,
               'schema': 'public',
               'f_name': 'bdg_listing_rent_flows_agent',
               'f_column': 'sk_listing_rent_flows',
               'dim_name': 'fact_listing_rent_flows',
               'dim_column': 'ods_id',
               'type': 'update'}
)

data_integrity_fact_listing_rent_flows_dim_booking = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_fact_demand_dim_booking',
    python_callable=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDB.BI_DW,
               'schema': 'public',
               'f_name': 'fact_listing_rent_flows',
               'f_column': 'sk_booking',
               'dim_name': 'dim_booking',
               'dim_column': 'sk_booking',
               'type': 'update'}
)

data_integrity_dim_agentreview_booking = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='data_integrity_dim_agentreview_booking',
    python_callable=guarantee_data_integrity,
    op_kwargs={'db_enum': EnumDB.BI_DW,
               'schema': 'public',
               'f_name': 'dim_agent_review',
               'f_column': 'sk_booking',
               'dim_name': 'dim_booking',
               'dim_column': 'sk_booking',
               'type': 'delete'}
)

refresh_agents = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='Refresh_PowerBI_Agents',
    python_callable=refresh_powerbi,
    op_kwargs={'workspace_name': 'Conversion', 'dataset_name': 'Agents'}
)

(bdg_listing_rent_flows_agent_xcom_dependencies >> bdg_listing_rent_flows_agent >> data_integrity_bdg_fact_agent >>
 data_integrity_bdg_dim_date >> data_integrity_bdg_dim_user >> data_integrity_dim_agentreview_booking >>
 data_integrity_fact_listing_rent_flows_dim_booking >> data_integrity_bdg_fact_listing_rent_flows >> refresh_agents)
