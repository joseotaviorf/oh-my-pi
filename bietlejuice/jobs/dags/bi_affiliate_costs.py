import json
import os
from datetime import datetime

import bietlejuice.jobs.base.new_base_etl as utils
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_etl import EnumDB
from bietlejuice.jobs.dags import DW_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.affiliate.affiliate import AffiliateETL
from bietlejuice.jobs.wrappers.GoogleDrive import GoogleSheets
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'DATA_AWS_ACCESS_KEY_ID',
                                 'DATA_AWS_SECRET_ACCESS_KEY')

# global vars
logger = QuintoAndarLogger('AffiliateCostsDAG')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
GOOGLE_S_A_CREDENTIALS = json.loads(env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')
GOOGLE_SHEETS_FILES = json.loads(env.get_airflow_env_var('BI_AFFILIATE_COSTS_GOOGLE_SHEETS_FILES'))
MAIN_DAG_ID = 'bi-affiliate-costs'
MAIN_START_DATE = datetime(2019, 11, 5)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('30 10 * * *')


def load_google_sheet_files_to_datalake(files):
    data_acc_aws_access_key_id = os.environ.get('DATA_AWS_ACCESS_KEY_ID')
    data_acc_aws_secret_access_key = os.environ.get('DATA_AWS_SECRET_ACCESS_KEY')
    athena_client = AthenaClient(s3_bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)
    gs = GoogleSheets(s3_bucket=s3_bucket, google_s_a_credentials=GOOGLE_S_A_CREDENTIALS,
                      google_api_scope=GOOGLE_API_SCOPE)
    for file in files:
        gs.move_sheets_data_to_destination(google_sheets_file=file,
                                           enumdb_destination=EnumDB.QuintoAndar_datalake,
                                           athena_client=athena_client)


def affiliate_append_monthly_data_to_dw_table(schema, file_name, table_name, date_column, **kwargs):
    AffiliateETL.append_monthly_data_to_dw_table(file_name=file_name, schema=schema, table_name=table_name,
                                                 execution_date=kwargs.get('execution_date'), date_column=date_column)


def affiliate_extract_query_from_ebdb_to_ods(schema, table_name, date_column, **kwargs):
    AffiliateETL.extract_query_from_ebdb_to_ods(s3_bucket=s3_bucket, schema=schema, table_name=table_name,
                                                date_column=date_column,
                                                execution_date=kwargs.get('execution_date'))


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

ods_fact_affiliate_daily_engagement_cost_task = BaseDAG.build_python_operator(
    task_id='ODS_fact_affiliate_daily_engagement_cost',
    dag=dag,
    provide_context=True,
    python_callable=affiliate_extract_query_from_ebdb_to_ods,
    op_kwargs={'schema': 'public',
               'table_name': 'affiliate_daily_engagement_cost',
               'date_column': 'ts_load'}
)

dw_fact_affiliate_daily_engagement_cost_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='DW_fact_affiliate_daily_engagement_cost',
    python_callable=utils.load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'affiliate_daily_engagement_cost',
               'schema_dest': 'marketing',
               'is_fact': True,
               'bucket': s3_bucket,
               'insert_dummy': False}
)

dw_fact_affiliate_daily_cost_attributions_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='DW_fact_affiliate_daily_cost_attributions',
    python_callable=BaseETL.move_file_query_data_to_db,
    op_kwargs={'schema': 'marketing',
               'file_name': '{}/marketing/affiliates_costs/fact_affiliate_daily_cost_attributions.sql'.format(
                   DW_QUERIES_DIR),
               'table_name': 'fact_affiliate_daily_cost_attributions',
               'append': False,
               'db_enum_source': EnumDB.BI_DW,
               'db_enum_destination': EnumDB.BI_DW}
)

dw_affiliates_national_campaigns_share_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='DW_affiliates_national_campaigns_share',
    python_callable=affiliate_append_monthly_data_to_dw_table,
    provide_context=True,
    op_kwargs={'schema': 'marketing',
               'file_name': '{}/marketing/affiliates_costs/affiliates_national_campaigns_share.sql'.format(
                   DW_QUERIES_DIR),
               'table_name': 'affiliates_national_campaigns_share',
               'date_column': 'year_month'}
)

load_historic_national_cost_to_datalake_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_historic_national_cost_to_datalake',
    python_callable=load_google_sheet_files_to_datalake,
    op_kwargs={'files': GOOGLE_SHEETS_FILES['historic_national_costs']}
)

ods_fact_affiliate_daily_engagement_cost_task >> dw_fact_affiliate_daily_engagement_cost_task
dw_fact_affiliate_daily_cost_attributions_task.set_upstream([dw_fact_affiliate_daily_engagement_cost_task,
                                                             load_affiliates_cost_to_datalake_task,
                                                             load_tradecom_config_to_datalake_task])
