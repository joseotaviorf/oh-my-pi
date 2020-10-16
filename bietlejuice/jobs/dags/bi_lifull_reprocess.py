import json
import os
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

MAIN_DAG_NAME = 'bi-lifull-reprocess'
MAIN_START_DATE = datetime(2019, 1, 1, 2, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('30 10 * * *')

env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
accounts = json.loads(env.get_airflow_env_var('bi-marketing-accounts'))

# API auth
auth = {
    MarketingEnum.LIFULL: None,
}

logger = QuintoAndarLogger(MAIN_DAG_NAME)

data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
athena_client = AthenaClient(s3_bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)

LIFULL_CAMPAIGNS_ACCOUNTS = accounts['lifull_campaigns']

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
    catchup=True,
    max_active_runs=1
)


def raw_sub_dag(sub_dag_name, class_, accounts):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        accounts=accounts,
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
        accounts=accounts,
        auth=auth[class_]
    )

    return sub_dag.build_tasks('clean')


def load_to_staging_sub_dag(sub_dag_name, class_):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
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
        auth=auth[class_]
    )

    return sub_dag.build_tasks('dw')


lifull_raw_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=raw_sub_dag,
    sub_dag_name='lifull-load-to-raw',
    class_=MarketingEnum.LIFULL,
    accounts=LIFULL_CAMPAIGNS_ACCOUNTS
)

lifull_clean_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=clean_sub_dag,
    sub_dag_name='lifull-raw-to-clean',
    class_=MarketingEnum.LIFULL,
    accounts=LIFULL_CAMPAIGNS_ACCOUNTS
)

lifull_load_to_staging_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_staging_sub_dag,
    sub_dag_name='lifull-load-to-staging',
    class_=MarketingEnum.LIFULL
)

lifull_load_to_dw_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_dw_sub_dag,
    sub_dag_name='lifull-load-to-dw',
    class_=MarketingEnum.LIFULL
)

airflow_helpers.chain(lifull_raw_dag,
                      lifull_clean_dag,
                      lifull_load_to_staging_dag,
                      lifull_load_to_dw_dag)
