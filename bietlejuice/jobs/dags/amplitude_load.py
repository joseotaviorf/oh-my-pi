from airflow.models import DAG
from datetime import datetime, timedelta

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.new_etl.amplitude.amplitude_events import AmplitudeEventsETL


def load_amplitude(**kwargs):
    start_date = kwargs['prev_execution_date']
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
    schedule_interval='@daily',
    max_active_runs=3
)

load_events_data_to_clean_task = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='load_events_data_to_clean',
    provide_context=True,
    func_command=load_amplitude
)
