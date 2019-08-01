import json
from datetime import datetime

from airflow.models import DAG
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.marketing.marketing_subdag_factory import \
    MarketingSubDagFactory
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum

BI_TWITTER_CAMPAIGNS_DAG_NAME = 'bi-twitter-campaigns'
MAIN_START_DATE = datetime(2019, 7, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('30 6 * * *')

env.set_airflow_var_to_local_env('BI_DW')
S3_BUCKET = env.get_airflow_env_var('bi-datalake-s3-bucket')
AUTH = json.loads(env.get_airflow_env_var('twitter_login'))

logger = QuintoAndarLogger(BI_TWITTER_CAMPAIGNS_DAG_NAME)


def raw_sub_dag(sub_dag_name, class_):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=BI_TWITTER_CAMPAIGNS_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        auth=AUTH,
        extra_configs={'days_offset': 0}
    )

    return sub_dag.build_tasks('raw')


main_dag = DAG(
    dag_id=BI_TWITTER_CAMPAIGNS_DAG_NAME,
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

twitter_raw_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=raw_sub_dag,
    sub_dag_name='twitter-load-to-raw',
    class_=MarketingEnum.TWITTER
)
