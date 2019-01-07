import airflow.utils.helpers as airflow_helpers
from airflow import DAG
from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.zendesk import ZendeskSubDag

MAIN_DAG_NAME = 'bi-zendesk'
MAIN_START_DATE = datetime(2018, 12, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 4 * * *')

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

ZENDESK_CLEAN_TABLES = env.get_airflow_env_var('bi-zendesk-tables').split(",")

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


def clean_sub_dag(sub_dag_name):
    sub_dag = ZendeskSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        tables=ZENDESK_CLEAN_TABLES
    )

    return sub_dag.build_tasks('clean')


def staging_sub_dag(sub_dag_name):
    sub_dag = ZendeskSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )

    return sub_dag.build_tasks('staging')


def prod_sub_dag(sub_dag_name):
    sub_dag = ZendeskSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )

    return sub_dag.build_tasks('prod')


clean_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=clean_sub_dag,
    sub_dag_name='zendesk-clean-sub-dag'
)

staging_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=staging_sub_dag,
    sub_dag_name='zendesk-staging-sub-dag'
)

prod_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=prod_sub_dag,
    sub_dag_name='zendesk-production-sub-dag'
)

airflow_helpers.chain(clean_dag, staging_dag, prod_dag)
