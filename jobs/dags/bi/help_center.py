import json
from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from jobs.dags.util import environment as env
from jobs.new_etl.help_center import HelpCenter
from qa_python_utils.default_logger import logger

# env vars
env.set_airflow_var_to_local_env('BI_DW')


@logger
def send_data_to_elasticsearch():
    help_center_json = env.get_airflow_env_var('help-center')
    help_center = HelpCenter(es_host=help_center_json['elasticsearch-host'])

    df = help_center.get_user_info()
    help_center.clean_elasticsearch()
    help_center.send_data_to_elasticsearch(df_user=df)


# dags
dag = DAG(
    dag_id='bi-help-center',
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
    task_id='send_universal_user_to_elasticsearch',
    python_callable=send_data_to_elasticsearch
)
