import os
from datetime import datetime, timedelta

import bietlejuice.jobs.base.new_base_etl as utils
from airflow.operators.dagrun_operator import TriggerDagRunOperator
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import (
    SOURCE_QUERIES_DIR,
    DW_QUERIES_DIR,
    DATALAKE_QUERIES_DIR,
)
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

logger = QuintoAndarLogger("bi-fact-listing-flows-agent-fix")

env.set_airflow_var_to_local_env("BI_DW", "BI_ODS")
bucket = env.get_airflow_env_var("bi-datalake-s3-bucket")

MAIN_DAG_NAME = "bi-fact-listing-flows-agent-fix"
MAIN_START_DATE = datetime(2018, 4, 29, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = "0 4 * * *"

# create main DAG definition
main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    description="ETL pipeline for the entire BI funnel",
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)

# create main DAG definition
main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    description="Fact listing flows agent fix",
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)


def load_dim_from_ods_to_dw(bucket, insert_dummy=True, schema_source='public', schema_dest='public'):
    table_name = 'vw_fact_house_listing_flows_agent_fix'
    table_name_dest = 'fact_house_listing_flows_agent_fix'
    path_with_schema = 'public'


    BaseETL.move_table_to_dw(
        table_name='{}.{}'.format(schema_source, table_name),
        table_name_dest='{}.{}'.format(schema_dest, table_name_dest),
        enum_db_source=EnumDB.BI_ODS,
        enum_db_dest=EnumDB.BI_DW,
        append=False,
        bucket_name='{}/clean/ods/{}'.format(bucket, path_with_schema),
        process_name='fact_house_listing_flows_agent_fix'
    )
    if insert_dummy:
        BaseETL.execute_command(
            command='insert into {} values (-1);'.format(table_name_dest),
            db_enum=EnumDB.BI_DW,
            commit=True
        )


def load_dim_from_ods_to_dw_dag():
    load_dim_from_ods_to_dw(
        bucket=bucket,
        insert_dummy=True,
        schema_dest="public",
        schema_source="public"
    )

dw_fact_listing_rent_flows_agent_fix = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="DW_Fact_Listing_Rent_Flows_Agent_Fix",
    python_callable=load_dim_from_ods_to_dw_dag,
)
