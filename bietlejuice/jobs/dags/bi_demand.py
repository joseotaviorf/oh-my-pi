from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.demand import DemandETL

env.set_airflow_var_to_local_env('BI_ODS', 'EBDB')
bucket_datalake = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_START_DATE = datetime(2019, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 0 * * *')


def extract_data_and_move_to_datalake(**kwargs):
    demand_etl = DemandETL(s3_bucket=bucket_datalake, execution_date=kwargs.get('execution_date'))
    df = demand_etl.extract_data(table_name=kwargs.get('table_name'))
    demand_etl.move_to_datalake(df=df, table_name=kwargs.get('table_name'))


dag = DAG(
    dag_id='bi-demand-test',
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

daily_active_users_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='daily_active_users',
    provide_context=True,
    python_callable=extract_data_and_move_to_datalake,
    op_kwargs={'table_name': 'daily_active_users'}
)

daily_active_user_sessions_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='daily_active_user_sessions',
    provide_context=True,
    python_callable=extract_data_and_move_to_datalake,
    op_kwargs={'table_name': 'daily_active_user_sessions'}
)

airflow_helpers.chain(daily_active_users_task, daily_active_user_sessions_task)
