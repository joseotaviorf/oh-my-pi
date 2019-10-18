import json
from datetime import datetime

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDB
from bietlejuice.jobs.wrappers.GoogleDrive import GoogleSheets
from bietlejuice.jobs.dags.util import environment as env

env.set_airflow_var_to_local_env('BI_ODS')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
GOOGLE_S_A_CREDENTIALS = json.loads(env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')
GOOGLE_SHEETS_FILES = json.loads(env.get_airflow_env_var('BI_AUX_REGIAO_GOOGLE_SHEETS_FILES'))
# NOTIFICATION_AUTH = json.loads(env.get_airflow_env_var('pr-notification-authorization'))

dag = DAG(
    dag_id='aux_regiao_test',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': True
    },
    start_date=datetime(2019, 10, 15, 0, 0, 0),
    schedule_interval='0 8 * * *',
    max_active_runs=1,
    orientation='TB',
    catchup=True
)


def load_google_sheet_files_to_datalake(files):
    gs = GoogleSheets(s3_bucket=s3_bucket, google_s_a_credentials=GOOGLE_S_A_CREDENTIALS,
                      google_api_scope=GOOGLE_API_SCOPE)
    # gs.move_sheets_data_to_destination(google_sheets_files=files,
    #                                    enumdb_destination=EnumDB.QuintoAndar_datalake,
    #                                    athena_client=athena_client)
    gs.move_sheets_data_to_destination(google_sheets_files=files,
                                       enumdb_destination=EnumDB.BI_ODS)


# def on_failure_callback(context):
#     """
#     Define the callback to post on Slack if a failure is detected in the Workflow
#     :return: operator.execute
#     """
#
#     operator = SlackAPIPostOperator(
#         task_id='failure',
#         text=str(context['task_instance']),
#         token=NOTIFICATION_AUTH,
#         channel='testebot'
#     )
#
#     return operator.execute(context=context)
#
#
# def on_success_callback(context):
#     """
#     Define the callback to post on Slack if a failure is detected in the Workflow
#     :return: operator.execute
#     """
#
#     operator = SlackAPIPostOperator(
#         task_id='success',
#         text=str(context['task_instance']),
#         token=NOTIFICATION_AUTH,
#         channel='testebot'
#     )
#
#     return operator.execute(context=context)


load_aux_regiao_to_datalake_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_aux_regiao_to_datalake_task',
    python_callable=load_google_sheet_files_to_datalake,
    op_kwargs={'files': GOOGLE_SHEETS_FILES['regiao']}
)
