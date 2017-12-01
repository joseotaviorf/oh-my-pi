from datetime import datetime
import os
import sys
import json

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, '../'))

from util import environment as env

here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, '../../'))

from new_etl.asterisk_calls import Asterisk

environment = env.get_environment('asterisk', 'bi-datalake-s3-bucket', 'BI_ODS', 'BI_DW', )
survey_queue_url = json.loads(environment['asterisk'])['survey_queue_url']
call_queue_url = json.loads(environment['asterisk'])['call_queue_url']
execution_time = datetime.now()
bucket = environment['bi-datalake-s3-bucket']

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


