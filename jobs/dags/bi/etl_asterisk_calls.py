import json
from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from jobs.dags.util import environment as env
from jobs.new_etl.asterisk_calls import Asterisk

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS')

asterisk_json = json.loads(env.get_airflow_env_var('asterisk')['asterisk'])

survey_queue_url = asterisk_json['survey_queue_url']
call_queue_url = asterisk_json['call_queue_url']
execution_time = datetime.now()
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

asterisk = Asterisk(execution_time, bucket)


def get_survey_data_from_sqs():
    survey_data = asterisk.get_asterisk_data_from_sqs(survey_queue_url)
    asterisk.save_asterisk_data_to_s3(survey_data, 'survey')


def get_calls_data_from_sqs():
    call_data = asterisk.get_asterisk_data_from_sqs(call_queue_url)
    asterisk.save_asterisk_data_to_s3(call_data, 'calls')


def purge_data_from_sqs():
    asterisk.delete_asterisk_messages(survey_queue_url)
    asterisk.delete_asterisk_messages(call_queue_url)


def save_data_to_dw():
    asterisk.save_asterisk_data_to_dw()


dag = DAG(
    dag_id='bi-asterisk-calls',
    default_args={
        'owner': 'Daniel Golhiardi',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 1, 1, 0, 0, 0),
    schedule_interval='0 * * * *',
    max_active_runs=1
)

get_survey_data_from_sqs_task = PythonOperator(
    dag=dag,
    task_id='get_survey_data_from_sqs',
    python_callable=get_survey_data_from_sqs
)

get_call_data_from_sqs_task = PythonOperator(
    dag=dag,
    task_id='get_call_data_from_sqs',
    python_callable=get_calls_data_from_sqs
)

delete_survey_messages_task = PythonOperator(
    dag=dag,
    task_id='delete_survey_messages',
    python_callable=purge_data_from_sqs
)

save_calls_to_dw_task = PythonOperator(
    dag=dag,
    task_id='save_calls_to_dw',
    python_callable=save_data_to_dw
)

# flow
get_call_data_from_sqs_task >> save_calls_to_dw_task
get_survey_data_from_sqs_task >> save_calls_to_dw_task
save_calls_to_dw_task >> delete_survey_messages_task
