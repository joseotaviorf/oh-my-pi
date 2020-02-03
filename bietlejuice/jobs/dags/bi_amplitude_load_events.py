from datetime import datetime, timedelta

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG, Variable
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.amplitude.amplitude_events import AmplitudeEventsETL
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

logger = QuintoAndarLogger('AmplitudeEvents')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
ENV = Variable.get("environment")
DB = f"datalake_amplitude_clean_{ENV}"


@logger(exclude='kwargs')
def xcom_amplitude_load_events(**kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    xcom.xcom_push(kwargs['ti'], exec_date)


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


@logger(exclude='kwargs')
def athena_execute_file_query_and_wait_for_results(filename, execution_date, bucket_folder_path, **kwargs):
    a = AthenaClient(s3_bucket=s3_bucket)

    bucket_folder_path = bucket_folder_path.format(
        dt=str(execution_date.strftime('%Y-%m-%d'))) if '{dt}' in bucket_folder_path else bucket_folder_path

    return_df = a.execute_file_query_and_return_dataframe(
        filename='{}/{}'.format(DATALAKE_QUERIES_DIR, filename),
        query_params={'ym': str(execution_date.strftime('%Y-%m')),
                      'dt': str(execution_date.strftime('%Y-%m-%d')),
                      'db': DB})

    suffix = '{}.csv'.format(str(execution_date))
    full_filename = '{}/{}'.format(bucket_folder_path, suffix)
    BaseETL.csv_to_s3(data=return_df, bucket=s3_bucket, filename=full_filename)

    # adding partition
    amplitude_etl = AmplitudeEventsETL(s3_bucket=s3_bucket)
    amplitude_etl.add_partition_active_user_sessions(execution_date=execution_date)


def load_active_user_sessions_clean(**kwargs):
    execution_date = kwargs['execution_date']

    amplitude_etl = AmplitudeEventsETL(s3_bucket=s3_bucket)
    df = amplitude_etl.get_active_user_sessions_treated(execution_date=execution_date)
    amplitude_etl.move_active_user_sessions_to_clean(df=df, execution_date=execution_date)


dag = DAG(
    dag_id='bi-amplitude-load-events',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 6, 0, 0, 0),
    schedule_interval='0 3 * * *',
    max_active_runs=3,
    catchup=True
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
    python_callable=load_amplitude_clean,
    execution_timeout=timedelta(hours=8)
)

xcom_amplitude_load_events_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='XCom_amplitude_load_events',
    python_callable=xcom_amplitude_load_events,
    provide_context=True
)

load_active_user_sessions_raw_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_active_user_sessions_raw',
    provide_context=True,
    python_callable=athena_execute_file_query_and_wait_for_results,
    op_kwargs={'filename': 'amplitude/active_user_sessions_raw.sql',
               'bucket_folder_path': 'raw/amplitude/active_user_sessions/dt={dt}'}

)

load_active_user_sessions_clean_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_active_user_sessions_clean',
    provide_context=True,
    python_callable=load_active_user_sessions_clean
)

xcom_active_user_sessions_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='XCom_active_user_sessions',
    python_callable=xcom_amplitude_load_events,
    provide_context=True
)

airflow_helpers.chain(load_events_to_raw_task,
                      load_events_to_clean_task,
                      load_active_user_sessions_raw_task,
                      load_active_user_sessions_clean_task,
                      xcom_active_user_sessions_task)
airflow_helpers.chain(load_events_to_clean_task, xcom_amplitude_load_events_task)
