import re
import json
import os
from datetime import datetime
from unidecode import unidecode

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.wrappers.GoogleDrive import GoogleSheets
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

logger = QuintoAndarLogger('GoogleSheetsDag')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
GOOGLE_S_A_CREDENTIALS = json.loads(env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')
GOOGLE_SHEETS_FILES = json.loads(env.get_airflow_env_var('GOOGLE_SHEETS_FILES'))

env.set_airflow_var_to_local_env('BI_ODS', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')


def load_google_sheet_files_to_datalake(file):
    data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
    data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
    athena_client = AthenaClient(s3_bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)
    gs = GoogleSheets(s3_bucket=s3_bucket, google_s_a_credentials=GOOGLE_S_A_CREDENTIALS,
                      google_api_scope=GOOGLE_API_SCOPE)
    gs.move_sheets_data_to_destination(google_sheets_file=file,
                                       enumdb_destination=EnumDB.QuintoAndar_datalake,
                                       athena_client=athena_client)


def load_google_sheet_files_to_ods(file):
    gs = GoogleSheets(s3_bucket=s3_bucket, google_s_a_credentials=GOOGLE_S_A_CREDENTIALS,
                      google_api_scope=GOOGLE_API_SCOPE)

    gs.move_sheets_data_to_destination(google_sheets_file=file,
                                       enumdb_destination=EnumDB.BI_ODS,
                                       drop_table=file['drop_table'])


def create_task_to_load_in_datalake(file):
    return BaseDAG.build_python_operator(
        dag=dag,
        task_id='load_{}_to_datalake'.format(file['s3_path']),
        pool='google_sheets_pool',
        python_callable=load_google_sheet_files_to_datalake,
        op_kwargs={'file': file}
    )


def create_task_to_load_in_ods(file):
    return BaseDAG.build_python_operator(
        dag=dag,
        task_id='load_{}_to_ods'.format(file['s3_path']),
        pool='google_sheets_pool',
        python_callable=load_google_sheet_files_to_ods,
        op_kwargs={'file': file}
    )


dag = DAG(
    dag_id='bi-google-sheets',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2019, 1, 1, 0, 0, 0),
    schedule_interval=env.convert_to_utc_schedule('0 0,11 * * *'),
    max_active_runs=1,
    catchup=False
)


for file in GOOGLE_SHEETS_FILES['files']:
    file['s3_path'] = re.sub('[^A-Za-z0-9]+', '_', unidecode(file['s3_path'])).lower()

    datalake_task = create_task_to_load_in_datalake(file)
    if file['send_to_ods']:
        ods_task = create_task_to_load_in_ods(file)
        datalake_task >> ods_task
