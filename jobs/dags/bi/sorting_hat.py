from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from jobs.dags.util import environment as env
from jobs.new_etl.sorting_hat import SortingHat
from qa_python_utils.default_logger import logger

# env vars
env.set_airflow_var_to_local_env('SORTINGHAT', 'BI_ODS')


# functions
@logger(exclude='kwargs')
def extract_table(**kwargs):
    table_name = kwargs['table_name']
    columns = '*' if 'columns' not in kwargs else kwargs['columns']

    sorting_hat = SortingHat()
    table = sorting_hat.extract_table_from_db(columns=columns, table_name=table_name)
    sorting_hat.load_table_to_s3(table_name=table_name,
                                 data_table=table,
                                 s3_bucket=env.get_airflow_env_var('bi-datalake-s3-bucket')
                                 )

    if 'load_to_ods' in kwargs and kwargs['load_to_ods'] is True:
        sorting_hat.load_table_to_ods(table_name=table_name.lower(), data_table=table)


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
    max_active_runs=1,
    catchup=False
)

# operators
PythonOperator(
    dag=dag,
    task_id='extract_proposal_table',
    python_callable=extract_table,
    op_kwargs={
        'table_name': 'Proposal',
        'columns': """id, imovel_id, analysis_date, "score_5A", "score_5A_best_subset", score_cardif,
                    score_cardif_best_subset, status, replace("comment", '\n', ' ') as "comment",
                    analyst_name, supervisor_name, rent_value, condo_value, iptu_value, created_at,
                    updated_at, home_area, home_bathrooms, home_bedrooms, home_city, home_garages,
                    home_region, home_suites, home_type, home_zipcode, drive_id, rejection_motive,
                    home_insurance_value, risk_level, risk_level_best_subset, process_date""",
        'load_to_ods': True
    }
)

PythonOperator(
    dag=dag,
    task_id='extract_proponent_table',
    python_callable=extract_table,
    op_kwargs={'table_name': 'Proponent'}
)
