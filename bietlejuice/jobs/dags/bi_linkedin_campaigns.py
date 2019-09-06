import json
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.marketing.marketing_subdag_factory import \
    MarketingSubDagFactory
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum

env.set_airflow_var_to_local_env('QA_PYTHON_UTILS_CREDENTIALS_JSON')

BI_LINKEDIN_CAMPAIGNS_DAG_NAME = 'bi-linkedin-campaigns'
MAIN_START_DATE = datetime(2019, 8, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('30 6 * * *')

env.set_airflow_var_to_local_env('BI_DW')
S3_BUCKET = env.get_airflow_env_var('bi-datalake-s3-bucket')

accounts = json.loads(env.get_airflow_env_var('bi-marketing-accounts'))

linkedin_gdrive_dir_id = env.get_airflow_env_var('LINKEDIN_GOOGLE_DRIVE_FOLDER_ID')

logger = QuintoAndarLogger(BI_LINKEDIN_CAMPAIGNS_DAG_NAME)


def raw_sub_dag(sub_dag_name, class_):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=BI_LINKEDIN_CAMPAIGNS_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        auth=None,
        extra_configs={'gdrive_dir_id': linkedin_gdrive_dir_id}
    )

    return sub_dag.build_tasks('raw')


def clean_sub_dag(sub_dag_name, class_):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=BI_LINKEDIN_CAMPAIGNS_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        auth=None,
        accounts=None
    )

    return sub_dag.build_tasks('clean')


def load_to_staging_sub_dag(sub_dag_name, class_):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=BI_LINKEDIN_CAMPAIGNS_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        auth=None,
        accounts=None
    )

    return sub_dag.build_tasks('staging')


def load_to_dw_sub_dag(sub_dag_name, class_):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=BI_LINKEDIN_CAMPAIGNS_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        auth=None
    )

    return sub_dag.build_tasks('dw')


main_dag = DAG(
    dag_id='bi-linkedin-campaigns',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=True
)

linkedin_raw_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=raw_sub_dag,
    sub_dag_name='linkedin-load-to-raw',
    class_=MarketingEnum.LINKEDIN
)

linkedin_clean_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=clean_sub_dag,
    sub_dag_name='linkedin-load-to-clean',
    class_=MarketingEnum.LINKEDIN
)

linkedin_staging_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_staging_sub_dag,
    sub_dag_name='linkedin-load-to-staging',
    class_=MarketingEnum.LINKEDIN
)

linkedin_ads_load_to_prod_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_dw_sub_dag,
    sub_dag_name='linkedin-load-to-dw',
    class_=MarketingEnum.LINKEDIN,
)

airflow_helpers.chain(linkedin_raw_sub_dag,
                      linkedin_clean_sub_dag,
                      linkedin_staging_sub_dag,
                      linkedin_ads_load_to_prod_sub_dag)
