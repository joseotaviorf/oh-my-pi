import json
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.marketing.marketing_subdag_factory import MarketingSubDagFactory
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum
from qa_python_utils.aws.athena import AthenaClient

MAIN_DAG_NAME = 'bi-marketing-classifieds-costs'
MAIN_START_DATE = datetime(2018, 1, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 0 * * *')

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
accounts = json.loads(env.get_airflow_env_var('bi-marketing-accounts'))

athena_client = AthenaClient(s3_bucket)

env.set_airflow_var_to_local_env('BI_DW')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

GOOGLE_S_A_CREDENTIALS = json.loads(env.get_airflow_env_var('bi-marketing-cost-service-account-gsheet-cred'))
MANUAL_COST_SHEET_ID = env.get_airflow_env_var('bi-marketing-cost-manual-sheet-id')

auth = {
    'sheet_credentials': GOOGLE_S_A_CREDENTIALS,
    'sheet_id': MANUAL_COST_SHEET_ID
}

# dags
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=False,
    max_active_runs=1
)


def raw_sub_dag(sub_dag_name, class_, auth):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        auth=auth
    )

    return sub_dag.build_tasks('raw')


def clean_sub_dag(sub_dag_name, class_, accounts, auth):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        accounts=accounts,
        auth=auth
    )

    return sub_dag.build_tasks('clean')


def load_to_staging_sub_dag(sub_dag_name, class_, auth):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        auth=auth
    )

    return sub_dag.build_tasks('staging')


def load_to_dw_sub_dag(sub_dag_name, class_, auth):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        auth=auth
    )

    return sub_dag.build_tasks('dw')


classifieds_raw_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=raw_sub_dag,
    sub_dag_name='classifieds-costs-load-to-raw',
    class_=MarketingEnum.CLASSIFIEDS_COSTS,
    auth=auth
)

classifieds_clean_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=clean_sub_dag,
    sub_dag_name='classifieds-costs-raw-to-clean',
    class_=MarketingEnum.CLASSIFIEDS_COSTS,
    accounts='default',
    auth=auth
)

classifieds_load_to_staging_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_staging_sub_dag,
    sub_dag_name='classifieds-costs-load-to-staging',
    class_=MarketingEnum.CLASSIFIEDS_COSTS,
    auth=auth
)

classifieds_load_to_dw_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_dw_sub_dag,
    sub_dag_name='classifieds-costs-load-to-dw',
    class_=MarketingEnum.CLASSIFIEDS_COSTS,
    auth=auth
)

airflow_helpers.chain(classifieds_raw_dag, classifieds_clean_dag,
                      classifieds_load_to_staging_dag, classifieds_load_to_dw_dag)
