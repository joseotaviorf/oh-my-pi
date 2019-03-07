import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.planner import PlannerFactory, PlannerTableEnum

# env vars
env.set_airflow_var_to_local_env('BI_DW')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_ID = 'bi-planner-load'
MAIN_START_DATE = datetime(2018, 1, 1)
# hits the API at 6, 7 and 8 a.m. to make sure we get at least one set of data
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 6,7,8 * * *')


# functions
def extract_and_load_data(_class, **kwargs):
    planner = PlannerFactory.factory(
        entity=_class,
        s3_bucket=s3_bucket,
        execution_date=kwargs['execution_date']
    )

    ids = planner.get_class_ids()
    for _id in ids:
        _data = planner.extract_data(id_class=_id)
        planner.save_into_s3_raw(_json=_data, id_class=_id)


def exec_class_method(_class, method, **kwargs):
    planner = PlannerFactory.factory(
        entity=_class,
        s3_bucket=s3_bucket,
        execution_date=kwargs['execution_date']
    )

    ids = planner.get_class_ids()
    for _id in ids:
        getattr(planner, method)(id_class=_id)


# dags
main_dag = DAG(
    dag_id=MAIN_DAG_ID,
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


def class_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_task = BaseDAG.build_python_operator(
        task_id='extract_data_into_raw',
        python_callable=extract_and_load_data,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class']
        }
    )

    upsert_raw_partition_task = BaseDAG.build_python_operator(
        task_id='upsert_raw_partition',
        python_callable=exec_class_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'upsert_single_raw_partition'
        }
    )

    move_to_clean_task = BaseDAG.build_python_operator(
        task_id='move_to_clean',
        python_callable=exec_class_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'move_to_clean'
        }
    )

    upsert_clean_partition_task = BaseDAG.build_python_operator(
        task_id='upsert_clean_partition',
        python_callable=exec_class_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'method': 'upsert_single_clean_partition'
        }
    )

    airflow_helpers.chain(
        extract_and_load_task,
        upsert_raw_partition_task,
        move_to_clean_task,
        upsert_clean_partition_task
    )

    return local_dag


# operators
region_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name=PlannerTableEnum.REGION.value,
    sub_dag_func=class_sub_dag,
    _class=PlannerTableEnum.REGION
)

# flow

# TODO: add unit tests
