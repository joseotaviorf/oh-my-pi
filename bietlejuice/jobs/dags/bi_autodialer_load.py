from datetime import datetime

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.autodialer import AutodialerETL, AutodialerEnum
from qa_python_utils import QuintoAndarLogger

env.set_airflow_var_to_local_env('BI_DW')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
mongo_client_uri = env.get_airflow_env_var('MONGODB_AUTODIALER_URI')

MAIN_DAG_NAME = 'bi-autodialer-load'
MAIN_START_DATE = datetime(2018, 11, 15, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 1 * * *')

logger = QuintoAndarLogger(MAIN_DAG_NAME)

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
        python_callable=execute_method,
        op_kwargs={'document_type_enum': document_type_enum,
                   'method': 'move_data_to_raw'}
    )

    clean_task = BaseDAG.build_python_operator(
        dag=local_dag,
        task_id='{}_to_clean'.format(document_type_enum.value),
        python_callable=execute_method,
        op_kwargs={'document_type_enum': document_type_enum,
                   'method': 'move_data_to_clean'}
    )

    raw_task >> clean_task

    return local_dag


@logger
def execute_method(document_type_enum, method):
    autodialer = AutodialerETL(
        mongo_client_uri=mongo_client_uri,
        bucket_name=s3_bucket,
        document_type_enum=document_type_enum
    )
    getattr(autodialer, method)()


task_references = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=autodialer_sub_dag,
    sub_dag_name=AutodialerEnum.TASK_REFERENCES.value,
    document_type_enum=AutodialerEnum.TASK_REFERENCES
)

task_reference_inbound_events = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=autodialer_sub_dag,
    sub_dag_name=AutodialerEnum.TASK_REFERENCE_INBOUND_EVENTS.value,
    document_type_enum=AutodialerEnum.TASK_REFERENCE_INBOUND_EVENTS
)

task_reference_outbound_events = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=autodialer_sub_dag,
    sub_dag_name=AutodialerEnum.TASK_REFERENCE_OUTBOUND_EVENTS.value,
    document_type_enum=AutodialerEnum.TASK_REFERENCE_OUTBOUND_EVENTS
)
