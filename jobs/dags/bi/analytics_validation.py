from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from jobs.dags.util import environment as env
from jobs.new_etl.analytics_data_validation.analytics_validation import SchemaValidator
from qa_python_utils.default_logger import logger


@logger(exclude='kwargs')
def validate_schemas(**kwargs):
    execution_date = kwargs['execution_date']
    schema_validator = SchemaValidator(
        execution_date=execution_date,
        s3_bucket=env.get_environment('bi-datalake-s3-bucket'))

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
