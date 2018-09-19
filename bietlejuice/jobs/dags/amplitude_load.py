from datetime import datetime, timedelta

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.new_etl.amplitude.amplitude_events import AmplitudeEventsETL


def load_amplitude(**kwargs):
    start_date = kwargs['execution_date']
    end_date = (start_date + timedelta(hours=23))
    a = AmplitudeEventsETL()
    a.extract_from_api_to_s3(start_date=start_date, end_date=end_date)


dag = DAG(
    dag_id='bi-amplitude-load-events',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 6, 0, 0, 0),
    schedule_interval='30 3 * * *',
    max_active_runs=3
)

load_events_data_to_clean_task = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='load_events_data_to_clean',
    provide_context=True,
    python_callable=load_amplitude
)
