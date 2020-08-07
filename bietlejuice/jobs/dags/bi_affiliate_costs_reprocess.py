from datetime import datetime, timedelta, time

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.affiliate.affiliate import AffiliateETL
from qa_python_utils import QuintoAndarLogger

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'DATA_ACC_AWS_ACCESS_KEY_ID',
                                 'DATA_ACC_AWS_SECRET_ACCESS_KEY')

# global vars
today_date = datetime.now().date()

logger = QuintoAndarLogger('AffiliateCostsDAG')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
MAIN_DAG_ID = 'bi-affiliate-costs-bug-reprocessing'
MAIN_START_DATE = datetime(2019, 10, 14)
MAIN_END_DATE = datetime.combine(today_date, time.min)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('30 10 * * *')


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
    end_date=MAIN_END_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=True
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
