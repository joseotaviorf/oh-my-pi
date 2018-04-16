from datetime import datetime

from airflow.models import DAG
# from airflow.models import Variable
# from airflow.operators.slack_operator import SlackAPIOperator
from airflow.operators.python_operator import PythonOperator
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.analytics_data_validation.analytics_validation import SchemaValidator
from qa_python_utils.default_logger import logger


@logger(exclude='kwargs')
def validate_schemas(**kwargs):
    execution_date = kwargs['execution_date']
    schema_validator = SchemaValidator(
        execution_date=execution_date,
        s3_bucket=env.get_airflow_env_var('bi-datalake-s3-bucket'))

    schema_validator.validate_events_and_save_into_s3()
    schema_validator.athena_client.execute_raw_query(
        'msck repair table datalake_clean.amplitude_schema_errors')


# def slack_failed_task(contextDictionary, **kwargs):
#     failed_alert = SlackAPIPostOperator(
#         task_id='failure',
#         text=str(context['task_instance']),
#         token=Variable.get("slack_access_token"),
#         channel=Variable.get("slack_channel"))
#     return failed_alert.execute


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
    python_callable=validate_schemas,
    # on_failure_callback=slack_failed_task
)
