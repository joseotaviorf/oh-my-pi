import json
from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import BranchPythonOperator
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.wrappers.GoogleDrive import GoogleSheets
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

logger = QuintoAndarLogger('ActionLineDag')
s3_bucket = env.get_airflow_env_var('wololo-s3-prod-bucket')
GOOGLE_S_A_CREDENTIALS = json.loads(env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')
ACTION_LINE_GOOGLE_SHEETS_FILES = json.loads(env.get_airflow_env_var('ACTION_LINE_GOOGLE_SHEETS_FILES'))
MAIN_DAG_ID = 'bi-action-line'
MAIN_START_DATE = datetime(2019, 7, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 11,18 * * *')


def load_google_sheet_files_to_datalake(file_name):
    athena_client = AthenaClient(s3_bucket)
    gs = GoogleSheets(s3_bucket=s3_bucket, google_s_a_credentials=GOOGLE_S_A_CREDENTIALS,
                      google_api_scope=GOOGLE_API_SCOPE)
    files = []
    for item in ACTION_LINE_GOOGLE_SHEETS_FILES['files']:
        if item['fileName'] == file_name:
            files.append(item)

    gs.move_sheets_data_to_destination(google_sheets_files=files,
                                       enumdb_destination=EnumDB.QuintoAndar_datalake,
                                       athena_client=athena_client,
                                       date_versioning=True,
                                       csv=True)


def verify_execution_time(execution_date, **kwargs):
    if int(execution_date.hour) == 14:
        return 'load_discarded_leads'
    elif int(execution_date.hour) == 21:
        return 'load_reorganize_leads'
    else:
        raise ValueError(
            'm=verify_execution_time, execution_date={}, msg=Execution Date not matching expected ones'.format(
                execution_date))


dag = DAG(
    dag_id=MAIN_DAG_ID,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False
)

verify_execution_time_branch = BranchPythonOperator(
    task_id='verify_execution_time',
    python_callable=verify_execution_time,
    provide_context=True,
    dag=dag)

load_reorganize_leads_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_reorganize_leads',
    python_callable=load_google_sheet_files_to_datalake,
    op_kwargs={'file_name': 'reorganize-leads'}
)

load_discarded_leads_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_discarded_leads',
    python_callable=load_google_sheet_files_to_datalake,
    op_kwargs={'file_name': 'discarded-leads'}
)

verify_execution_time_branch >> load_reorganize_leads_task
verify_execution_time_branch >> load_discarded_leads_task
