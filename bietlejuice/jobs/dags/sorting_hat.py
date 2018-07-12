from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.sorting_hat import unit_tests
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.sorting_hat import SortingHat

# env vars
env.set_airflow_var_to_local_env('SORTINGHAT', 'BI_ODS')
MAIN_DAG_NAME = 'bi-sorting-hat'
MAIN_START_DATE = datetime(2018, 1, 14, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = '0 4 * * *'


# functions
@logger(exclude='kwargs')
def extract_table(**kwargs):
    table_name = kwargs['table_name']

    sorting_hat = SortingHat()
    table = sorting_hat.extract_table_from_db(query_file_path=kwargs['query_file_path_suffix'])
    sorting_hat.load_table_to_s3(table_name=table_name,
                                 data_table=table,
                                 s3_bucket=env.get_airflow_env_var('bi-datalake-s3-bucket')
                                 )

    if 'load_to_ods' in kwargs and kwargs['load_to_ods'] is True:
        sorting_hat.load_table_to_ods(table_name=table_name.lower(), data_table=table)


# dags
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False
)


def unit_tests_sub_dag(sub_dag_name, **kwargs):
    return unit_tests.build(
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        entity=kwargs['entity']
    )


# operators
proposal_task = PythonOperator(
    dag=main_dag,
    task_id='extract_proposal_table',
    python_callable=extract_table,
    op_kwargs={
        'table_name': 'Proposal',
        'query_file_path_suffix': 'proposal.sql',
        'load_to_ods': True
    }
)

proposalversion_task = PythonOperator(
    dag=main_dag,
    task_id='extract_proposal_version_table',
    python_callable=extract_table,
    op_kwargs={
        'table_name': 'ProposalVersion',
        'query_file_path_suffix': 'proposal_version.sql',
        'load_to_ods': True
    }
)

proponent_task = PythonOperator(
    dag=main_dag,
    task_id='extract_proponent_table',
    python_callable=extract_table,
    op_kwargs={
        'table_name': 'Proponent',
        'query_file_path_suffix': 'proponent.sql'
    }
)

# unit tests
proposal_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=unit_tests_sub_dag,
    sub_dag_name='proposal_unit_tests',
    entity='proposal'
)

proponent_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=unit_tests_sub_dag,
    sub_dag_name='proponent_unit_tests',
    entity='proponent'
)

proposalversion_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=unit_tests_sub_dag,
    sub_dag_name='proposalversion_unit_tests',
    entity='proposalversion'
)

# flow
proposal_task >> proposal_unit_tests_dag
proposalversion_task >> proposalversion_unit_tests_dag
proponent_task >> proponent_unit_tests_dag
