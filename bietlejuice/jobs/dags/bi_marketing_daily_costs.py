from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.operators.dagrun_operator import TriggerDagRunOperator
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl import DW_QUERIES_DIR
from qa_python_utils import QuintoAndarLogger

env.set_airflow_var_to_local_env('BI_DW')

MAIN_DAG_NAME = 'bi-marketing-daily-costs'
MAIN_START_DATE = datetime(2019, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1,7,13,19 * * *')

logger = QuintoAndarLogger(MAIN_DAG_NAME)

# create DAG definition
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    description='ETL Pipeline for unifying marketing costs from various sources',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False
)


def move_file_query_data_to_dw(schema, file_name):
    query = BaseETL.get_query_from_file_name(file_name='{}/{}/{}.sql'.format(DW_QUERIES_DIR, schema, file_name))

    table = BaseETL.from_db_query(
        db_enum=EnumDB.BI_DW,
        query=query)

    BaseETL.bulk_insert(
        table=table,
        table_name='{}.{}'.format(schema, file_name),
        db_enum=EnumDB.BI_DW,
        encoding='UTF-8',
        append=False
    )


load_fact_marketing_daily_costs_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='load_fact_marketing_daily_costs',
    python_callable=move_file_query_data_to_dw,
    op_kwargs={'schema': 'marketing',
               'file_name': 'fact_marketing_daily_costs'}
)

# trigger bi-marketing-funnels-conversions after all tasks have been successfully completed
trigger_bi_marketing_funnels_conversions_task = TriggerDagRunOperator(
    dag=main_dag,
    task_id='trigger_bi_marketing_funnels_conversions',
    trigger_dag_id='bi-marketing-funnels-conversions',
    execution_date='{{ execution_date }}'
)

airflow_helpers.chain(load_fact_marketing_daily_costs_task, trigger_bi_marketing_funnels_conversions_task)
