import os
import sys
from datetime import datetime

from airflow.models import DAG
from qa_python_utils.default_logger import logger
from jobs.newetl.analytics_data_validation.analytics_validation import SchemaValidator
from airflow.operators.quintoandar import QuintoAndarPythonOperator

here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, '../'))


@logger(exclude='kwargs')
def validate_schemas(**kwargs):
    execution_date = kwargs['execution_date']
    schema_validator = SchemaValidator(execution_date)

    schema_validator.validate_events_and_save_into_s3()
    schema_validator.athena_client.execute_raw_query(
        'msck repair table datalake_clean.amplitude_schema_errors')


dag = DAG(
    dag_id='bi-analytics-data-validation',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2017, 11, 20, 0, 0, 0),
    schedule_interval='0 4 * * *',
    max_active_runs=1)

QuintoAndarPythonOperator(
    dag=dag,
    task_id='validate_schemas',
    provide_context=True,
    python_callable=validate_schemas)
