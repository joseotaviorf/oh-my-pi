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

MAIN_DAG_NAME = 'bi-marketing-classifieds-costs-reprocess'
MAIN_START_DATE = datetime(2019, 4, 2, 0, 0, 0)
MAIN_END_DATE = datetime(2019, 8, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 0 * * *')

env.set_airflow_var_to_local_env('BI_DW')
S3_BUCKET = env.get_airflow_env_var('bi-datalake-s3-bucket')

GOOGLE_S_A_CREDENTIALS = json.loads(
    env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
MANUAL_COST_SHEETS = json.loads(env.get_airflow_env_var('BI_MKT_COST_MANUAL_SHEETS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')

SIDE_DEMAND = 'demand'
SIDE_SUPPLY = 'supply'

AUTH = {'GSA_CREDENTIALS': GOOGLE_S_A_CREDENTIALS, 'GOOGLE_API_SCOPE': GOOGLE_API_SCOPE}

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


def raw_sub_dag(sub_dag_name, class_, auth, extra_configs):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        end_date=MAIN_END_DATE,
        auth=auth,
        extra_configs=extra_configs
    )

    return sub_dag.build_tasks('raw')


def clean_sub_dag(sub_dag_name, class_, auth, extra_configs):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        end_date=MAIN_END_DATE,
        auth=auth,
        extra_configs=extra_configs
    )

    return sub_dag.build_tasks('clean')


def load_to_staging_sub_dag(sub_dag_name, class_, auth):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        end_date=MAIN_END_DATE,
        auth=auth
    )

    return sub_dag.build_tasks('staging')


def load_to_dw_sub_dag(sub_dag_name, class_, auth):
    sub_dag = MarketingSubDagFactory.factory(
        class_=class_,
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        end_date=MAIN_END_DATE,
        auth=auth
    )

    return sub_dag.build_tasks('dw')


# Supply
supply_classifieds_raw_subdag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=raw_sub_dag,
    sub_dag_name='supply-classifieds-costs-load-to-raw',
    class_=MarketingEnum.CLASSIFIEDS_COSTS,
    auth=AUTH,
    extra_configs={'side': SIDE_SUPPLY, 'sheet_id': MANUAL_COST_SHEETS['supply_costs']}
)

supply_classifieds_clean_subdag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=clean_sub_dag,
    sub_dag_name='supply-classifieds-costs-raw-to-clean',
    class_=MarketingEnum.CLASSIFIEDS_COSTS,
    auth=AUTH,
    extra_configs={'side': SIDE_SUPPLY}
)

# Supply&Demand
supply_demand_classifieds_load_to_staging_subdag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_staging_sub_dag,
    sub_dag_name='supply-demand-classifieds-costs-load-to-staging',
    class_=MarketingEnum.CLASSIFIEDS_COSTS,
    auth=AUTH
)

supply_demand_classifieds_load_to_dw_subdag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=load_to_dw_sub_dag,
    sub_dag_name='supply-demand-classifieds-costs-load-to-dw',
    class_=MarketingEnum.CLASSIFIEDS_COSTS,
    auth=AUTH
)

airflow_helpers.chain(supply_classifieds_raw_subdag, supply_classifieds_clean_subdag)

supply_demand_classifieds_load_to_staging_subdag.set_upstream(supply_classifieds_clean_subdag)
airflow_helpers.chain(supply_demand_classifieds_load_to_staging_subdag,
                      supply_demand_classifieds_load_to_dw_subdag)
