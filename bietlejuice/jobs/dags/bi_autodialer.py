from datetime import datetime

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.autodialer.autodialer import AutodialerETL
from bietlejuice.jobs.new_etl.autodialer.autodialer_enum import AutodialerEnum
from qa_python_utils import QuintoAndarLogger

env.set_airflow_var_to_local_env('BI_DW')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_NAME = 'bi-autodialer-with-subdags'
MAIN_START_DATE = datetime(2018, 11, 15, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')

logger = QuintoAndarLogger(MAIN_DAG_NAME)

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


def autodialer_sub_dag(sub_dag_name, document_type_enum):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    raw_task = BaseDAG.build_python_operator(
        dag=local_dag,
        task_id='{}_to_raw'.format(document_type_enum.value),
        python_callable=move_to_raw,
        provide_context=True,
        op_kwargs={'document_type_enum': document_type_enum}
    )

    clean_task = BaseDAG.build_python_operator(
        dag=local_dag,
        task_id='{}_to_clean'.format(document_type_enum.value),
        python_callable=move_to_clean,
        provide_context=True,
        op_kwargs={'document_type_enum': document_type_enum}
    )

    raw_task >> clean_task

    return local_dag


@logger(exclude='kwargs')
def move_to_raw(**kwargs):
    autodialer = AutodialerETL(
        bucket_name=s3_bucket,
        document_type_enum=kwargs['document_type_enum']
    )
    autodialer.move_data_to_raw()


@logger(exclude='kwargs')
def move_to_clean(**kwargs):
    autodialer = AutodialerETL(
        bucket_name=s3_bucket,
        document_type_enum=kwargs['document_type_enum']
    )
    autodialer.move_data_to_clean()


task_references = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=autodialer_sub_dag,
    sub_dag_name='{}_move_to_raw_and_clean'.format(AutodialerEnum.TASK_REFERENCES.value),
    document_type_enum=AutodialerEnum.TASK_REFERENCES
)

task_reference_inbound_events = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=autodialer_sub_dag,
    sub_dag_name='{}_move_to_raw_and_clean'.format(AutodialerEnum.TASK_REFERENCE_INBOUND_EVENTS.value),
    document_type_enum=AutodialerEnum.TASK_REFERENCE_INBOUND_EVENTS
)

task_reference_outbound_events = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=autodialer_sub_dag,
    sub_dag_name='{}_move_to_raw_and_clean'.format(AutodialerEnum.TASK_REFERENCE_OUTBOUND_EVENTS.value),
    document_type_enum=AutodialerEnum.TASK_REFERENCE_OUTBOUND_EVENTS
)
