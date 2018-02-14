from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from jobs.dags.util import environment as env
from jobs.new_etl.sorting_hat import SortingHat
from qa_python_utils.default_logger import logger

# env vars
env.set_airflow_var_to_local_env('SORTINGHAT')


# functions
@logger(exclude='kwargs')
def extract_table(**kwargs):
    table_name = kwargs['table_name']

    sorting_hat = SortingHat()
    table = sorting_hat.extract_table_from_db(table_name=table_name)
    sorting_hat.load_table_to_s3(table_name=table_name,
                                 table=table,
                                 s3_bucket=env.get_environment('bi-datalake-s3-bucket')
                                 )


# dags
dag = DAG(
    dag_id='bi-sorting-hat',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 1, 14, 0, 0, 0),
    schedule_interval='0 4 * * *',
    max_active_runs=1
)

# operators
PythonOperator(
    dag=dag,
    task_id='extract_proposal_table',
    python_callable=extract_table,
    op_kwargs={'table_name': 'Proposal'}
)

PythonOperator(
    dag=dag,
    task_id='extract_proponent_table',
    python_callable=extract_table,
    op_kwargs={'table_name': 'Proponent'}
)
