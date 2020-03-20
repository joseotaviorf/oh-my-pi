import json
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.operators.dagrun_operator import TriggerDagRunOperator
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl import DW_QUERIES_DIR
from bietlejuice.jobs.wrappers.GoogleDrive import GoogleSheets
from qa_python_utils import QuintoAndarLogger

env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
GOOGLE_S_A_CREDENTIALS = json.loads(env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')
GOOGLE_SHEETS_FILES = json.loads(env.get_airflow_env_var('MARKETING_GOOGLE_SHEETS_FILES'))
MAIN_DAG_NAME = 'bi-marketing-daily-costs'
MAIN_START_DATE = datetime(2019, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1,7,13,19 * * *')

logger = QuintoAndarLogger(MAIN_DAG_NAME)


def load_google_sheet_files_to_datalake(files):
    gs = GoogleSheets(s3_bucket=s3_bucket, google_s_a_credentials=GOOGLE_S_A_CREDENTIALS,
                      google_api_scope=GOOGLE_API_SCOPE)
    for file in files:
        gs.move_sheets_data_to_destination(google_sheets_file=file,
                                           enumdb_destination=EnumDB.QuintoAndar_datalake,
                                           csv=True)


# create DAG definition
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    description='ETL Pipeline for unifying marketing costs from various sources',
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


def move_file_query_data_to_dw(schema, file_name):
    query = BaseETL.get_query_from_file_name(file_name='{}/{}/{}.sql'.format(DW_QUERIES_DIR, schema, file_name))

    table = BaseETL.from_db_query(
        db_enum=EnumDB.BI_DW,
        query=query)

    BaseETL.bulk_insert(
        table=table,
        table_name='{}.{}'.format(schema, file_name),
        db_enum=EnumDB.BI_DW,
        encoding='UTF-8',
        append=False
    )


load_shared_manual_costs_to_datalake_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='load_shared_manual_costs_to_datalake',
    python_callable=load_google_sheet_files_to_datalake,
    op_kwargs={'files': GOOGLE_SHEETS_FILES['files']}
)

load_fact_marketing_daily_costs_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='load_fact_marketing_daily_costs',
    python_callable=move_file_query_data_to_dw,
    op_kwargs={'schema': 'marketing',
               'file_name': 'fact_marketing_daily_costs'}
)

# trigger bi-marketing-funnels-conversions after all tasks have been successfully completed
trigger_bi_marketing_funnels_conversions_task = TriggerDagRunOperator(
    dag=main_dag,
    task_id='trigger_bi_marketing_funnels_conversions',
    trigger_dag_id='bi-marketing-funnels-conversions',
    execution_date='{{ execution_date }}'
)

airflow_helpers.chain(
    load_shared_manual_costs_to_datalake_task,
    load_fact_marketing_daily_costs_task,
    trigger_bi_marketing_funnels_conversions_task)
