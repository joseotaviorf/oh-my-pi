import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from datetime import datetime, timedelta
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.amplitude.amplitude_events import AmplitudeEventsETL

logger = QuintoAndarLogger('AmplitudeEvents')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')


@logger(exclude='kwargs')
def load_amplitude(**kwargs):
    start_date = kwargs['execution_date'].replace(hour=0, minute=0, second=0, microsecond=0)
    end_date = (start_date + timedelta(hours=23))

    amplitude_etl = AmplitudeEventsETL(s3_bucket=s3_bucket)
    amplitude_etl.extract_from_api_to_s3(start_date=start_date, end_date=end_date)


@logger(exclude='kwargs')
def load_amplitude_clean(**kwargs):
    execution_date = kwargs['execution_date']

    amplitude_etl = AmplitudeEventsETL(s3_bucket=s3_bucket)
    amplitude_etl.load_data_to_clean(execution_date=execution_date)


dag = DAG(
    dag_id='bi-amplitude-load-events',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 6, 0, 0, 0),
    schedule_interval='30 3 * * *',
    max_active_runs=3,
    catchup=False
)

load_events_to_raw_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_events_to_raw',
    provide_context=True,
    python_callable=load_amplitude
)

load_events_to_clean_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_events_to_clean',
    provide_context=True,
    python_callable=load_amplitude_clean
)

airflow_helpers.chain(load_events_to_raw_task,
                      load_events_to_clean_task)
