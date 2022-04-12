from datetime import datetime

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
# from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.sorting_hat import unit_tests
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.sorting_hat import SortingHat
from qa_python_utils import QuintoAndarLogger

# env vars
env.set_airflow_var_to_local_env('SORTINGHAT', 'BI_ODS', 'DATA_AWS_ACCESS_KEY_ID', 'DATA_AWS_SECRET_ACCESS_KEY')
MAIN_DAG_NAME = 'bi-sorting-hat'
MAIN_START_DATE = datetime(2018, 1, 14, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = '0 4 * * *'

logger = QuintoAndarLogger(MAIN_DAG_NAME)


# functions
@logger(exclude='kwargs')
def extract_table(**kwargs):
    table_name = kwargs['table_name']

    table = SortingHat.extract_table_from_db(query_file_path=kwargs['query_file_path_suffix'],
                                             query_param={'execution_date': kwargs[
                                                 'execution_date']} if 'execution_date' in kwargs else None)

    sorting_hat = SortingHat()
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
        entity=kwargs['entity'],
        use_query_param=kwargs.get('use_query_param')
    )


# operators
proposal_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='extract_proposal_table',
    python_callable=extract_table,
    provide_context=True,
    op_kwargs={
        'table_name': 'Proposal',
        'query_file_path_suffix': 'proposal.sql',
        'load_to_ods': True
    }
)

proposal_version_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='extract_proposal_version_table',
    python_callable=extract_table,
    provide_context=True,
    op_kwargs={
        'table_name': 'ProposalVersion',
        'query_file_path_suffix': 'proposal_version.sql',
        'load_to_ods': True
    }
)

proponent_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='extract_proponent_table',
    python_callable=extract_table,
    op_kwargs={
        'table_name': 'Proponent',
        'query_file_path_suffix': 'proponent.sql'
    }
)

external_score_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='extract_external_score',
    python_callable=extract_table,
    provide_context=True,
    op_kwargs={
        'table_name': 'ExternalScore',
        'query_file_path_suffix': 'external_score.sql'
    }
)

screening_result_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='extract_screening_result',
    python_callable=extract_table,
    provide_context=True,
    op_kwargs={
        'table_name': 'ScreeningResult',
        'query_file_path_suffix': 'screening_result.sql'
    }
)

# unit tests
# proposal_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=unit_tests_sub_dag,
#     sub_dag_name='proposal_unit_tests',
#     entity='proposal',
#     use_query_param=True
# )

# proponent_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=unit_tests_sub_dag,
#     sub_dag_name='proponent_unit_tests',
#     entity='proponent'
# )

# proposal_version_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=unit_tests_sub_dag,
#     sub_dag_name='proposal_version_unit_tests',
#     entity='proposal_version',
#     use_query_param=True
# )

# external_score_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=unit_tests_sub_dag,
#     sub_dag_name='external_score_unit_tests',
#     entity='external_score',
#     use_query_param=True
# )

# screening_result_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=unit_tests_sub_dag,
#     sub_dag_name='screening_result_unit_tests',
#     entity='screening_result'
# )
