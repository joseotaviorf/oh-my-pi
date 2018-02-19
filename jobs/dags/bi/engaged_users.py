from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from jobs.dags.util import environment as env
from jobs.new_etl.amplitude.engaged_users import EngagedUsers
from qa_python_utils.default_logger import logger

env.set_airflow_var_to_local_env('BI_DW')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

# create DAG definition
main_dag = DAG(
    dag_id='bi-amplitude-engaged-users',
    description='ETL pipeline for finding Amplitude engaged users',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 18, 0, 0, 0),
    schedule_interval=env.convert_to_utc_schedule('0 5 * * *'),
    max_active_runs=1
)


@logger
def materialize_engaged_users_table_query(**kwargs):
    _filter = kwargs['filter']

    engaged_users = EngagedUsers(bucket)
    engaged_users.append_to_table(_filter=_filter)


def get_python_operator(task_id, func_command, op_kwargs=None):
    return PythonOperator(
        dag=main_dag,
        task_id=task_id,
        python_callable=func_command,
        op_kwargs=op_kwargs
    )


all_task = get_python_operator('extract_data', materialize_engaged_users_table_query, op_kwargs={'filter': 'all'})
city_task = get_python_operator('extract_data', materialize_engaged_users_table_query, op_kwargs={'filter': 'city'})
region_task = get_python_operator('extract_data', materialize_engaged_users_table_query, op_kwargs={'filter': 'region'})

# must be sequencial because of the appending operation
all_task >> city_task >> region_task
