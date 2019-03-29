import json
import time
from datetime import datetime, timedelta

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.aws.batch import BatchClient
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.marketing.marketing_subdag_factory import \
    MarketingSubDagFactory
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum

MAIN_DAG_NAME = 'bi-marketing-costs'
MAIN_START_DATE = datetime(2018, 12, 10, 2, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('30 0,6,12,18 * * *')

env.set_airflow_var_to_local_env('BI_DW')

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
accounts = json.loads(env.get_airflow_env_var('bi-marketing-accounts'))

# API auth
auth = {
    MarketingEnum.RTB: json.loads(env.get_airflow_env_var('rtb_login')),
    MarketingEnum.CRITEO: json.loads(env.get_airflow_env_var('criteo_login')),
    MarketingEnum.FACEBOOK_ADS: None,
    MarketingEnum.GOOGLE_ADS: None,
    MarketingEnum.TROVIT: None
}

logger = QuintoAndarLogger(MAIN_DAG_NAME)

athena_client = AthenaClient(s3_bucket)

FACEBOOK_ADS_ACCOUNTS = accounts['facebook_ads']

GOOGLE_ADS_ACCOUNTS = accounts['google_ads']

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


def raw_sub_dag(sub_dag_name, class_):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
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


def load_to_pre_staging_sub_dag(sub_dag_name, class_, accounts):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
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


def scrap_trovit_data(**kwargs):
    logger.info('m={}, msg={}'.format('scrap_trovit_data', 'Starting job...'))
    start_date = (kwargs['execution_date'] - timedelta(days=1)).strftime(
        '%Y-%m-%d')
    batch_client = BatchClient()
    job_name = 'scrap-trovit-data'
    job_queue = 'scrap-marketing-data'
    r = batch_client.start_batch_job(
        job_name=job_name,
        job_queue=job_queue,
        job_definition='scrap-marketing-data:1',
        command=['scrapy', 'crawl', 'trovit', '-a', 'start_date={}'.format(start_date), '-a',
                 'end_date={}'.format(start_date)]
    )

    while not (batch_client.get_job_info_by_id(r.get('jobId')).get('status') in ('SUCCEEDED', 'FAILED')):
        time.sleep(30)

    final_status = batch_client.get_job_info_by_id(r.get('jobId')).get('status')

    if final_status == 'FAILED':
        raise RuntimeError('m={}, msg={}'.format('scrap_trovit_data', 'Job {} failed.'.format(r.get('jobName'))))

    logger.info('m={}, msg=Job {} ended successfully'.format('scrap_trovit_data', r.get('jobName')))


# facebook_ads_clean_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=clean_sub_dag,
#     sub_dag_name="facebook-ads-raw-to-clean",
#     class_=MarketingEnum.FACEBOOK_ADS,
#     accounts=FACEBOOK_ADS_ACCOUNTS
# )
#
# facebook_ads_load_to_pre_staging_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=load_to_pre_staging_sub_dag,
#     sub_dag_name='facebook-ads-load-to-pre-staging',
#     class_=MarketingEnum.FACEBOOK_ADS,
#     accounts=FACEBOOK_ADS_ACCOUNTS
# )
#
# facebook_ads_load_to_staging_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=load_to_staging_sub_dag,
#     sub_dag_name='facebook-ads-load-to-staging',
#     class_=MarketingEnum.FACEBOOK_ADS
# )
#
# facebook_ads_load_to_dw_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=load_to_dw_sub_dag,
#     sub_dag_name='facebook-ads-load-to-dw',
#     class_=MarketingEnum.FACEBOOK_ADS
# )
#
# google_ads_clean_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=clean_sub_dag,
#     sub_dag_name='google-ads-raw-to-clean',
#     class_=MarketingEnum.GOOGLE_ADS,
#     accounts=GOOGLE_ADS_ACCOUNTS
# )
#
# google_ads_load_to_pre_staging_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=load_to_pre_staging_sub_dag,
#     sub_dag_name='google-ads-load-to-pre-staging',
#     class_=MarketingEnum.GOOGLE_ADS,
#     accounts=GOOGLE_ADS_ACCOUNTS
# )
#
# google_ads_load_to_staging_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=load_to_staging_sub_dag,
#     sub_dag_name='google-ads-load-to-staging',
#     class_=MarketingEnum.GOOGLE_ADS,
# )
#
# google_ads_load_to_dw_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=load_to_dw_sub_dag,
#     sub_dag_name='google-ads-load-to-dw',
#     class_=MarketingEnum.GOOGLE_ADS,
# )
#
# criteo_raw_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=raw_sub_dag,
#     sub_dag_name='criteo-load-to-raw',
#     class_=MarketingEnum.CRITEO,
# )
#
# criteo_clean_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=clean_sub_dag,
#     sub_dag_name='criteo-raw-to-clean',
#     class_=MarketingEnum.CRITEO,
#     accounts='default'
# )
#
# criteo_load_to_staging_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=load_to_staging_sub_dag,
#     sub_dag_name='criteo-load-to-staging',
#     class_=MarketingEnum.CRITEO,
# )
#
# criteo_load_to_dw_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=load_to_dw_sub_dag,
#     sub_dag_name='criteo-load-to-dw',
#     class_=MarketingEnum.CRITEO,
# )
#
# rtb_raw_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=raw_sub_dag,
#     sub_dag_name='rtb-load-to-raw',
#     class_=MarketingEnum.RTB
# )
#
# rtb_clean_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=clean_sub_dag,
#     sub_dag_name='rtb-raw-to-clean',
#     class_=MarketingEnum.RTB,
#     accounts='default'
# )
#
# rtb_load_to_staging_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=load_to_staging_sub_dag,
#     sub_dag_name='rtb-load-to-staging',
#     class_=MarketingEnum.RTB,
# )
#
# rtb_load_to_dw_dag = BaseSubDag.get_sub_dag_operator(
#     dag=main_dag,
#     sub_dag_func=load_to_dw_sub_dag,
#     sub_dag_name='rtb-load-to-dw',
#     class_=MarketingEnum.RTB,
# )

trovit_data_to_raw = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='scrap-trovit-data',
    python_callable=scrap_trovit_data,
    provide_context=True,
    op_kwargs=None
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

# airflow_helpers.chain(google_ads_clean_dag,
#                       google_ads_load_to_pre_staging_dag,
#                       google_ads_load_to_staging_dag,
#                       google_ads_load_to_dw_dag)
# airflow_helpers.chain(facebook_ads_clean_dag,
#                       facebook_ads_load_to_pre_staging_dag,
#                       facebook_ads_load_to_staging_dag,
#                       facebook_ads_load_to_dw_dag)
# airflow_helpers.chain(criteo_raw_dag,
#                       criteo_clean_dag,
#                       criteo_load_to_staging_dag,
#                       criteo_load_to_dw_dag)
# airflow_helpers.chain(rtb_raw_dag,
#                       rtb_clean_dag,
#                       rtb_load_to_staging_dag,
#                       rtb_load_to_dw_dag)
airflow_helpers.chain(trovit_data_to_raw,
                      trovit_clean_dag,
                      trovit_load_to_staging_dag,
                      trovit_load_to_dw_dag)
