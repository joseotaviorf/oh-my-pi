from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from jobs.dags.util import environment as env
from jobs.new_etl.s3_files_to_ods import S3ToODS

# env vars
env.set_airflow_var_to_local_env('BI_ODS')


# functions
def move_files_to_ods():
    s3_to_ods = S3ToODS(
        s3_bucket=env.get_airflow_env_var('bi-datalake-s3-bucket'),
        xls_s3_bucket=env.get_airflow_env_var('bi-etl-ejuice-xls2ods')
    )
    s3_to_ods.move_files_to_ods()


# dags
dag = DAG(
    dag_id='bi-s3_to_ods',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 1, 1, 0, 0, 0),
    schedule_interval='0 4 * * *',
    max_active_runs=1
)

# operators
PythonOperator(
    dag=dag,
    task_id='move_files_to_ods',
    python_callable=move_files_to_ods
)
