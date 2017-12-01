import os
import sys
from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from qa_python_utils.default_logger import logger

from util import environment as env

here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, '../../'))

from new_etl.analytics_data_validation.analytics_validation import SchemaValidator

environment = env.get_environment('bi-datalake-s3-bucket')
bucket = environment['bi-datalake-s3-bucket']

@logger(exclude='kwargs')
def validate_schemas(**kwargs):
    execution_date = kwargs['execution_date']
    schema_validator = SchemaValidator(execution_date, bucket)

    schema_validator.validate_events_and_save_into_s3()
    schema_validator.athena_client.execute_raw_query('msck repair table datalake_clean.amplitude_schema_errors')


dag = DAG(
    dag_id='bi-analytics-data-validation',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 1, 1, 0, 0, 0),
    schedule_interval='0 4 * * *',
    max_active_runs=1
)

PythonOperator(
    dag=dag,
    task_id='validate_schemas',
    provide_context=True,
    python_callable=validate_schemas
)
