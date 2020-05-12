from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.operators.python_operator import ShortCircuitOperator
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.etl.crm.task_titles import CRMTaskTitles
from bietlejuice.jobs.etl.crm.tasks import CRMTasks
from bietlejuice.jobs.etl.crm.workgroups import CRMWorkgroups
from bietlejuice.jobs.etl.crm.workflows import CRMWorkflows
from bietlejuice.jobs.etl.crm.task_status_histories import CRMTaskStatusHistories

# ---------------------------------------------------------------
# ---------------------------------------------------------------
# This DAG is a dependency of the bi-crm-dw DAG. If it fails and
# bi-crm-dw was already triggered at the current date, we need to
# clear manually the execution of the bi-crm-dw to rerun it.
# ---------------------------------------------------------------
# ---------------------------------------------------------------

# env vars
env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
mongo_client_uri = env.get_airflow_env_var('MONGODB_CRM_URI')

MAIN_DAG_ID = 'bi-crm-load'
MAIN_START_DATE = datetime(2018, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 0 * * *')


# functions
def data_existence_check(bucket_type, **kwargs):
    crm_tasks = CRMTasks(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    return crm_tasks.data_existence_check(bucket_type)


def upsert_partition(bucket_type, method, **kwargs):
    crm_tasks = CRMTasks(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    getattr(crm_tasks, method)(bucket_type)


def extract_and_load_tasks_data(**kwargs):
    crm_tasks = CRMTasks(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_tasks.extract_and_load_data()


def extract_and_load_workflows_data(**kwargs):
    crm_workflows = CRMWorkflows(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_workflows.extract_and_load_data()


def workflows_data_existence_check(bucket_type, **kwargs):
    crm_workflows = CRMWorkflows(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    return crm_workflows.data_existence_check(bucket_type)


def upsert_workflows_partition(bucket_type, **kwargs):
    crm_workflows = CRMWorkflows(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_workflows.upsert_workflows_partition(bucket_type)


def move_workflows_to_clean(**kwargs):
    crm_workflows = CRMWorkflows(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_workflows.move_worflows_to_clean()


def extract_and_load_task_status_histories_data(**kwargs):
    crm_task_status_histories = CRMTaskStatusHistories(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_task_status_histories.extract_and_load_data()


def task_status_histories_data_existence_check(bucket_type, **kwargs):
    crm_task_status_histories = CRMTaskStatusHistories(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    return crm_task_status_histories.data_existence_check(bucket_type)


def upsert_task_status_histories_partition(bucket_type, **kwargs):
    crm_task_status_histories = CRMTaskStatusHistories(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    crm_task_status_histories.upsert_task_status_histories_partition(bucket_type)


def extract_and_load_workgroups_data(**kwargs):
    crm_workgroups = CRMWorkgroups(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri
    )

    crm_workgroups.extract_and_load_data()


def move_workgroups_to_clean(**kwargs):
    crm_workgroups = CRMWorkgroups(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri
    )

    crm_workgroups.move_workgroups_to_clean()


def extract_and_load_task_titles_data(**kwargs):
    crm_task_titles = CRMTaskTitles(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri
    )

    crm_task_titles.extract_and_load_data()


def move_task_titles_to_clean(**kwargs):
    crm_task_titles = CRMTaskTitles(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri
    )

    crm_task_titles.move_task_titles_to_clean()


def exec_crm_method(method, **kwargs):
    crm_tasks = CRMTasks(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    getattr(crm_tasks, method)()


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
    orientation='TB',
    catchup=False
)


def workgroups_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_workgroups_task = BaseDAG.build_python_operator(
        task_id='extract_and_load_workgroups',
        python_callable=extract_and_load_workgroups_data,
        dag=local_dag
    )

    move_workgroups_to_clean_task = BaseDAG.build_python_operator(
        task_id='move_workgroups_to_clean',
        python_callable=move_workgroups_to_clean,
        dag=local_dag
    )

    extract_and_load_workgroups_task >> move_workgroups_to_clean_task

    return local_dag


def task_titles_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_task_titles_task = BaseDAG.build_python_operator(
        task_id='extract_and_load_task_titles',
        python_callable=extract_and_load_task_titles_data,
        dag=local_dag
    )

    move_task_titles_to_clean_task = BaseDAG.build_python_operator(
        task_id='move_task_titles_to_clean',
        python_callable=move_task_titles_to_clean,
        dag=local_dag
    )

    extract_and_load_task_titles_task >> move_task_titles_to_clean_task

    return local_dag


def workflows_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_workflows_task = BaseDAG.build_python_operator(
        task_id='extract_and_load_workflows',
        python_callable=extract_and_load_workflows_data,
        dag=local_dag,
        provide_context=True
    )

    check_data_existence = BaseDAG.build_python_operator(
        task_id='check_data_existence',
        python_callable=workflows_data_existence_check,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'raw'
        }
    )

    upsert_workflows_partition_task = BaseDAG.build_python_operator(
        task_id='upsert_workflows_raw_partition',
        python_callable=upsert_workflows_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'raw'
        }
    )

    move_workflows_to_clean_task = BaseDAG.build_python_operator(
        task_id='move_workflows_to_clean',
        python_callable=move_workflows_to_clean,
        dag=local_dag,
        provide_context=True
    )

    upsert_workflows_clean_partitions_task = BaseDAG.build_python_operator(
        task_id='upsert_workflows_clean_partition',
        python_callable=upsert_workflows_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'clean'
        }
    )

    airflow_helpers.chain(
        extract_and_load_workflows_task,
        check_data_existence,
        upsert_workflows_partition_task,
        move_workflows_to_clean_task,
        upsert_workflows_clean_partitions_task
    )

    return local_dag


def task_status_histories_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_task_status_histories_task = BaseDAG.build_python_operator(
        task_id='extract_and_load_task_status_histories',
        python_callable=extract_and_load_task_status_histories_data,
        dag=local_dag,
        provide_context=True
    )

    check_data_existence = BaseDAG.build_python_operator(
        task_id='check_data_existence',
        python_callable=task_status_histories_data_existence_check,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'raw'
        }
    )

    upsert_task_status_histories_partition_task = BaseDAG.build_python_operator(
        task_id='upsert_task_status_histories_raw_partition',
        python_callable=upsert_task_status_histories_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'raw'
        }
    )

    airflow_helpers.chain(
        extract_and_load_task_status_histories_task,
        check_data_existence,
        upsert_task_status_histories_partition_task,
    )

    return local_dag


def clean_tasks_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    move_tasks_to_clean_task = BaseDAG.build_python_operator(
        task_id='move_tasks_to_clean',
        python_callable=exec_crm_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'method': 'move_tasks_to_clean'
        }
    )

    upsert_tasks_clean_partition_task = BaseDAG.build_python_operator(
        task_id='upsert_tasks_clean_partition',
        python_callable=upsert_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'clean',
            'method': 'upsert_tasks_partition'
        }
    )

    move_tasks_to_clean_task >> upsert_tasks_clean_partition_task

    return local_dag


def clean_task_resolution_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    move_tasks_resolution_to_clean_task = BaseDAG.build_python_operator(
        task_id='move_tasks_resolution_to_clean',
        python_callable=exec_crm_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'method': 'move_tasks_resolution_to_clean'
        }
    )

    upsert_tasks_resolution_clean_partition_task = BaseDAG.build_python_operator(
        task_id='upsert_tasks_resolution_clean_partition',
        python_callable=upsert_partition,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'clean',
            'method': 'upsert_tasks_resolution_partition'
        }
    )

    move_tasks_resolution_to_clean_task >> upsert_tasks_resolution_clean_partition_task

    return local_dag


def xcom_crm_load(**kwargs):
    exec_date = str(datetime.date(kwargs["execution_date"]))
    xcom.xcom_push(kwargs["ti"], exec_date)


# operators
extract_and_load_tasks_task = BaseDAG.build_python_operator(
    task_id='extract_and_load_tasks',
    python_callable=extract_and_load_tasks_data,
    dag=main_dag,
    provide_context=True
)

data_existence_check_task = ShortCircuitOperator(
    task_id='data_existence_check',
    python_callable=data_existence_check,
    dag=main_dag,
    provide_context=True,
    op_kwargs={
        'bucket_type': 'raw'
    }
)

upsert_raw_partition_task = BaseDAG.build_python_operator(
    task_id='upsert_raw_partition',
    python_callable=upsert_partition,
    dag=main_dag,
    provide_context=True,
    op_kwargs={
        'bucket_type': 'raw',
        'method': 'upsert_tasks_partition'
    }
)

workgroups_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='workgroups',
    sub_dag_func=workgroups_sub_dag,
)

task_titles_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='task_titles',
    sub_dag_func=task_titles_sub_dag,
)

clean_tasks_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='create_clean_tasks_table',
    sub_dag_func=clean_tasks_sub_dag,
)

clean_tasks_resolution_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='create_clean_tasks_resolution_table',
    sub_dag_func=clean_task_resolution_sub_dag,
)

xcom_crm_load_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="XCom_crm_load",
    python_callable=xcom_crm_load,
    provide_context=True,
)

workflows_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='workflows',
    sub_dag_func=workflows_sub_dag,
    provide_context=True
)

task_status_histories_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='task_status_histories',
    sub_dag_func=task_status_histories_sub_dag,
    provide_context=True
)

# flow
airflow_helpers.chain(
    extract_and_load_tasks_task,
    data_existence_check_task,
    upsert_raw_partition_task,
    clean_tasks_sub_dag_task,
    clean_tasks_resolution_sub_dag_task,
    [workgroups_sub_dag_task, task_titles_sub_dag_task]
)

xcom_crm_load_task.set_upstream([workgroups_sub_dag_task, task_titles_sub_dag_task])

# TODO: add unit tests
