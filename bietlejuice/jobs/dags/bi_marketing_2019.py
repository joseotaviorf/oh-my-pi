import json
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.marketing.marketing_subdag_factory import \
    MarketingSubDagFactory
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import QuintoAndarLogger

MAIN_DAG_NAME = 'bi-marketing-costs-2019'
MAIN_START_DATE = datetime(2018, 12, 31, 0, 0, 0)
MAIN_END_DATE = datetime(2019, 4, 15, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 3 * * *')

env.set_airflow_var_to_local_env('BI_DW')

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
accounts = json.loads(env.get_airflow_env_var('bi-marketing-accounts'))

# API auth
auth = {
    MarketingEnum.RTB: json.loads(env.get_airflow_env_var('rtb_login')),
    MarketingEnum.TROVIT: None
}

logger = QuintoAndarLogger(MAIN_DAG_NAME)

athena_client = AthenaClient(s3_bucket)

# dags
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    end_date=MAIN_END_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=True,
    max_active_runs=1
)


def raw_sub_dag(sub_dag_name, class_):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        end_date=MAIN_END_DATE,
        auth=auth[class_]
    )

    return sub_dag.build_tasks('raw')


def clean_sub_dag(sub_dag_name, class_, accounts):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        end_date=MAIN_END_DATE,
        accounts=accounts,
        auth=auth[class_]
    )

    return sub_dag.build_tasks('clean')


def load_to_pre_staging_sub_dag(sub_dag_name, class_, accounts):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        end_date=MAIN_END_DATE,
        accounts=accounts
    )

    return sub_dag.build_tasks('pre_staging')


def load_to_staging_sub_dag(sub_dag_name, class_):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        end_date=MAIN_END_DATE,
        auth=auth[class_]
    )

    return sub_dag.build_tasks('staging')


def load_to_dw_sub_dag(sub_dag_name, class_):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        end_date=MAIN_END_DATE,
        auth=auth[class_]
    )

    return sub_dag.build_tasks('dw')


rtb_raw_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=raw_sub_dag,
    sub_dag_name='rtb-load-to-raw',
    class_=MarketingEnum.RTB
)

rtb_clean_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=clean_sub_dag,
    sub_dag_name='rtb-raw-to-clean',
    class_=MarketingEnum.RTB,
    accounts='default'
)

rtb_load_to_staging_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_staging_sub_dag,
    sub_dag_name='rtb-load-to-staging',
    class_=MarketingEnum.RTB,
)

rtb_load_to_dw_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_dw_sub_dag,
    sub_dag_name='rtb-load-to-dw',
    class_=MarketingEnum.RTB,
)

trovit_raw_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=raw_sub_dag,
    sub_dag_name='trovit-load-to-raw',
    class_=MarketingEnum.TROVIT
)

trovit_clean_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=clean_sub_dag,
    sub_dag_name='trovit-raw-to-clean',
    class_=MarketingEnum.TROVIT,
    accounts='default'
)

trovit_load_to_staging_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_staging_sub_dag,
    sub_dag_name='trovit-load-to-staging',
    class_=MarketingEnum.TROVIT
)

trovit_load_to_dw_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_dw_sub_dag,
    sub_dag_name='trovit-load-to-dw',
    class_=MarketingEnum.TROVIT
)

airflow_helpers.chain(rtb_raw_dag,
                      rtb_clean_dag,
                      rtb_load_to_staging_dag,
                      rtb_load_to_dw_dag)
airflow_helpers.chain(trovit_raw_dag,
                      trovit_clean_dag,
                      trovit_load_to_staging_dag,
                      trovit_load_to_dw_dag)
