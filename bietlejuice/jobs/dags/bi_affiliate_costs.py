import json
from datetime import datetime

import bietlejuice.jobs.base.new_base_etl as utils
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_etl import EnumDB
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.wrappers.GoogleDrive import GoogleSheets
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB')

# global vars
logger = QuintoAndarLogger('AffiliateCostsDAG')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
GOOGLE_S_A_CREDENTIALS = json.loads(env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')
GOOGLE_SHEETS_FILES = json.loads(env.get_airflow_env_var('BI_AFFILIATE_COSTS_GOOGLE_SHEETS_FILES'))
MAIN_DAG_ID = 'bi-affiliate-costs'
MAIN_START_DATE = datetime(2019, 10, 14)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 10 * * *')


def delete_daily_rows(db_enum, table_name, date_column, value):
    BaseETL.execute_command(
        command="delete from {} where date({}) = date('{}')".format(table_name, date_column, value),
        db_enum=db_enum,
        encoding='utf-8',
        commit=True
    )


def extract_query_from_ebdb_to_ods(table_name, date_column, **kwargs):
    if 'execution_date' not in kwargs:
        raise ValueError('m=extract_query_from_ebdb_to_ods, msg=execution_date is mandatory.')

    file_path = '{}/ebdb/affiliates/{}.sql'.format(SOURCE_QUERIES_DIR, table_name)
    query = BaseETL.get_query_from_file_name(file_name=file_path)

    delete_daily_rows(db_enum=EnumDB.BI_ODS, table_name=table_name, date_column=date_column,
                      value=str(kwargs['execution_date']))

    utils.extract_query_dim_from_ebdb_to_ods(
        dim_name=table_name,
        bucket=s3_bucket,
        command=query.format(str_date=str(kwargs['execution_date'])),
        table_name=table_name,
        append=True
    )


def load_google_sheet_files_to_datalake(files):
    athena_client = AthenaClient(s3_bucket)
    gs = GoogleSheets(s3_bucket=s3_bucket, google_s_a_credentials=GOOGLE_S_A_CREDENTIALS,
                      google_api_scope=GOOGLE_API_SCOPE)
    gs.move_sheets_data_to_destination(google_sheets_files=files,
                                       enumdb_destination=EnumDB.QuintoAndar_datalake,
                                       athena_client=athena_client)


dag = DAG(
    dag_id=MAIN_DAG_ID,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': True
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=True
)

load_affiliates_cost_to_datalake_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_affiliates_cost_to_datalake',
    python_callable=load_google_sheet_files_to_datalake,
    op_kwargs={'files': GOOGLE_SHEETS_FILES['costs']}
)

load_tradecom_config_to_datalake_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_tradecom_config_to_datalake',
    python_callable=load_google_sheet_files_to_datalake,
    op_kwargs={'files': GOOGLE_SHEETS_FILES['tradecom_config']}
)

ods_fact_affiliate_daily_engagement_cost = BaseDAG.build_python_operator(
    task_id='ODS_fact_affiliate_daily_engagement_cost',
    dag=dag,
    provide_context=True,
    python_callable=extract_query_from_ebdb_to_ods,
    op_kwargs={'table_name': 'affiliate_daily_engagement_cost',
               'date_column': 'dt_cost'}
)

dw_fact_affiliate_daily_engagement_cost = BaseDAG.build_python_operator(
    dag=dag,
    task_id='DW_fact_affiliate_daily_engagement_cost',
    python_callable=utils.load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'affiliate_daily_engagement_cost',
               'schema_dest': 'marketing', 'is_fact': True, 'bucket': s3_bucket,
               'insert_dummy': False}
)

ods_fact_affiliate_daily_engagement_cost >> dw_fact_affiliate_daily_engagement_cost
