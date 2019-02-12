from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.kill_queue.reservation_subdag import ReservationSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.kill_queue import KillQueueFactory, KillQueueTableEnum

logger = QuintoAndarLogger('bi-killqueue-etl')

env.set_airflow_var_to_local_env('KILLQUEUE', 'BI_ODS')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_NAME = 'bi-killqueue-etl'
MAIN_START_DATE = datetime(2019, 1, 27)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')


def run_factory_method(table, method):
    kill_queue_obj = KillQueueFactory.get_object(
        table=table,
        s3_bucket=s3_bucket
    )
    getattr(kill_queue_obj, method)()


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
    max_active_runs=1,
    catchup=False
)


def create_datalake_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_data_and_move_to_raw = BaseDAG.build_python_operator(
        task_id='extract_data_and_move_to_raw',
        python_callable=run_factory_method,
        dag=local_dag,
        provide_context=False,
        op_kwargs={
            'table': kwargs['table'],
            'method': 'extract_data_and_move_to_raw'
        }
    )

    move_data_from_raw_to_clean = BaseDAG.build_python_operator(
        task_id='move_data_from_raw_to_clean',
        python_callable=run_factory_method,
        dag=local_dag,
        provide_context=False,
        op_kwargs={
            'table': kwargs['table'],
            'method': 'move_data_from_raw_to_clean'
        }
    )

    airflow_helpers.chain(
        extract_data_and_move_to_raw,
        move_data_from_raw_to_clean
    )

    return local_dag


def reservation_sub_dag(sub_dag_name):
    sub_dag = ReservationSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )
    return sub_dag.build_tasks_with_tests()


# operators
house_to_datalake_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='house-to-datalake',
    sub_dag_func=create_datalake_sub_dag,
    table=KillQueueTableEnum.HOUSE
)

rent_flow_to_datalake_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='rent-flow-to-datalake',
    sub_dag_func=create_datalake_sub_dag,
    table=KillQueueTableEnum.RENT_FLOW
)

reservation_to_datalake_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='reservation-to-datalake',
    sub_dag_func=create_datalake_sub_dag,
    table=KillQueueTableEnum.RESERVATION
)

reservation_aud_to_datalake_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='reservation-aud-to-datalake',
    sub_dag_func=create_datalake_sub_dag,
    table=KillQueueTableEnum.RESERVATION_AUD
)

reservation_subdag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='reservation',
    sub_dag_func=reservation_sub_dag

)

reservation_subdag.set_upstream(
    [house_to_datalake_task, rent_flow_to_datalake_task, reservation_to_datalake_task,
     reservation_aud_to_datalake_task])
