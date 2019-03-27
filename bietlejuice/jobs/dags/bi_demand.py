from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.demand import DemandFactory, DemandEnum

bucket_datalake = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_START_DATE = datetime(2019, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 7 * * *')


def extract_data_and_move_to_datalake(table, period):
    demand_etl = DemandFactory.factory(class_=table,
                                       s3_bucket=bucket_datalake)
    df = demand_etl.extract_data(period=period)
    demand_etl.move_to_datalake(df=df, period=period)


dag = DAG(
    dag_id='bi-demand',
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
    python_callable=extract_data_and_move_to_datalake,
    op_kwargs={'table': DemandEnum.ACTIVE_USERS,
               'period': 'daily'}
)

daily_active_user_sessions_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='daily_active_user_sessions',
    python_callable=extract_data_and_move_to_datalake,
    op_kwargs={'table': DemandEnum.ACTIVE_USER_SESSIONS,
               'period': 'daily'}
)

weekly_active_users_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='weekly_active_users',
    python_callable=extract_data_and_move_to_datalake,
    op_kwargs={'table': DemandEnum.ACTIVE_USERS,
               'period': 'weekly'}
)

weekly_active_user_sessions_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='weekly_active_user_sessions',
    python_callable=extract_data_and_move_to_datalake,
    op_kwargs={'table': DemandEnum.ACTIVE_USER_SESSIONS,
               'period': 'weekly'}
)

monthly_active_users_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='monthly_active_users',
    python_callable=extract_data_and_move_to_datalake,
    op_kwargs={'table': DemandEnum.ACTIVE_USERS,
               'period': 'monthly'}
)

monthly_active_user_sessions_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='monthly_active_user_sessions',
    python_callable=extract_data_and_move_to_datalake,
    op_kwargs={'table': DemandEnum.ACTIVE_USER_SESSIONS,
               'period': 'monthly'}
)

airflow_helpers.chain(daily_active_users_task, daily_active_user_sessions_task, weekly_active_users_task,
                      weekly_active_user_sessions_task, monthly_active_users_task, monthly_active_user_sessions_task)
