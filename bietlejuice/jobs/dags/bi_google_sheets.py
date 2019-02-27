import json
from datetime import datetime

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.wrappers.GoogleDrive import GoogleSheets
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('GoogleSheetsDag')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
GOOGLE_S_A_CREDENTIALS = json.loads(env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')
GOOGLE_SHEETS_FILES = json.loads(env.get_airflow_env_var('GOOGLE_SHEETS_FILES'))


def load_google_sheet_files():
    gs = GoogleSheets(s3_bucket=s3_bucket)
    gs.move_sheets_data_to_datalake(google_s_a_credentials=GOOGLE_S_A_CREDENTIALS,
                                    google_api_scope=GOOGLE_API_SCOPE,
                                    google_sheets_files=GOOGLE_SHEETS_FILES,
                                    list_filenames=['DAU Taxonomy'])
    # TODO
    # get dynamically all files from GOOGLE_SHEETS_FILES


dag = DAG(
    dag_id='bi-google-sheets',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2019, 1, 1, 0, 0, 0),
    schedule_interval='0 0 * * *',
    max_active_runs=3,
    catchup=False
)

load_google_sheet_files_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_google_sheet_files_to_datalake',
    python_callable=load_google_sheet_files
)
