from datetime import datetime
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.new_etl.amplitude.amplitude_events import AmplitudeEventsETL

DEFAULT_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'
AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
LOCAL_TZ = 'America/Sao_Paulo'


def load_amplitude(**kwargs):
    exec_date = kwargs['execution_date']
    prev_exec_date = kwargs['prev_execution_date']
    a = AmplitudeEventsETL()
    a.run_source_to_sns(start_date=prev_exec_date, end_date=exec_date)


dag = DAG(
    dag_id='bi-amplitude-load',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 6, 0, 0, 0),
    schedule_interval='@hourly',
    max_active_runs=1
)

load_events_data_to_clean_task = BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='load_events_data_to_clean',
    provide_context=True,
    func_command=load_amplitude
)
