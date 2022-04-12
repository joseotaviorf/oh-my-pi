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
env.set_airflow_var_to_local_env('BI_DW', 'DATA_AWS_ACCESS_KEY_ID', 'DATA_AWS_SECRET_ACCESS_KEY')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
mongo_client_uri = env.get_airflow_env_var('MONGODB_CRM_URI')

MAIN_DAG_ID = 'bi-crm-load'
MAIN_START_DATE = datetime(2018, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 0 * * *')


# functions
def exec_workflows_method(method, **kwargs):
    crm = CRMWorkflows(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    return getattr(crm, method)(**kwargs)


def exec_task_status_histories_method(method, **kwargs):
    crm = CRMTaskStatusHistories(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    return getattr(crm, method)(**kwargs)


def exec_workgroups_method(method, **kwargs):
    crm = CRMWorkgroups(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri
    )

    getattr(crm, method)()


def exec_task_titles_method(method, **kwargs):
    crm = CRMTaskTitles(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri
    )

    getattr(crm, method)()


def exec_crm_method(method, **kwargs):
    crm_tasks = CRMTasks(
        s3_bucket=s3_bucket,
        mongo_client_uri=mongo_client_uri,
        execution_date=kwargs['execution_date']
    )

    return getattr(crm_tasks, method)(**kwargs)


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


def full_load_sub_dag(sub_dag_name, python_exec, python_method, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_raw_tasks = BaseDAG.build_python_operator(
        task_id='extract_and_load_raw_data',
        dag=local_dag,
        python_callable=python_exec,
        op_kwargs={
            'method': python_method['extract_and_load']
        }
    )

    move_to_clean_task = BaseDAG.build_python_operator(
        task_id='move_to_clean',
        dag=local_dag,
        python_callable=python_exec,
        op_kwargs={
            'method': python_method['move_to_clean']
        }
    )

    extract_and_load_raw_tasks >> move_to_clean_task

    return local_dag


def incremental_raw_sub_dag(sub_dag_name, python_exec, python_method, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    extract_and_load_task = BaseDAG.build_python_operator(
        task_id='extract_and_load',
        python_callable=python_exec,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'method': python_method['extract_and_load_data']
        }
    )

    check_data_existence = ShortCircuitOperator(
        task_id='check_data_existence',
        python_callable=python_exec,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'raw',
            'method': python_method['data_existence_check']
        }
    )

    upsert_partition_task = BaseDAG.build_python_operator(
        task_id='upsert_raw_partition',
        python_callable=python_exec,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'raw',
            'method': python_method['upsert_partition']
        }
    )

    airflow_helpers.chain(
        extract_and_load_task,
        check_data_existence,
        upsert_partition_task,
    )

    return local_dag


def incremental_clean_sub_dag(sub_dag_name, python_exec, python_method, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    move_to_clean_task = BaseDAG.build_python_operator(
        task_id='move_to_clean',
        python_callable=python_exec,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'method': python_method['move_to_clean']
        }
    )

    upsert_clean_partitions_task = BaseDAG.build_python_operator(
        task_id='upsert_clean_partition',
        python_callable=python_exec,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'bucket_type': 'clean',
            'method': python_method['upsert_clean_partition']
        }
    )

    airflow_helpers.chain(
        move_to_clean_task,
        upsert_clean_partitions_task
    )

    return local_dag


def xcom_crm_load(**kwargs):
    exec_date = str(datetime.date(kwargs["execution_date"]))
    xcom.xcom_push(kwargs["ti"], exec_date)


# operators
tasks_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='incremental_load_raw_tasks',
    python_exec=exec_crm_method,
    python_method={
        'extract_and_load_data': 'extract_and_load_data',
        'data_existence_check': 'data_existence_check',
        'upsert_partition': 'upsert_tasks_partition'
    },
    sub_dag_func=incremental_raw_sub_dag,
    provide_context=True
)

tasks_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='incremental_load_clean_tasks',
    python_exec=exec_crm_method,
    python_method={
        'move_to_clean': 'move_tasks_to_clean',
        'upsert_clean_partition': 'upsert_tasks_partition'
    },
    sub_dag_func=incremental_clean_sub_dag,
    provide=True
)

workgroups_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='full_load_workgroups',
    python_exec=exec_workgroups_method,
    python_method={
        'extract_and_load': 'extract_and_load_data',
        'move_to_clean': 'move_workgroups_to_clean'
    },
    sub_dag_func=full_load_sub_dag
)

task_titles_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='full_load_task_titles',
    python_exec=exec_task_titles_method,
    python_method={
        'extract_and_load': 'extract_and_load_data',
        'move_to_clean': 'move_task_titles_to_clean'
    },
    sub_dag_func=full_load_sub_dag
)

clean_tasks_resolution_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='incremental_load_clean_tasks_resolution_table',
    python_exec=exec_crm_method,
    python_method={
        'move_to_clean': 'move_tasks_resolution_to_clean',
        'upsert_clean_partition': 'upsert_tasks_resolution_partition'
    },
    sub_dag_func=incremental_clean_sub_dag,
)

clean_task_resolution_history_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='incremental_load_clean_task_resolution_history_table',
    python_exec=exec_task_status_histories_method,
    python_method={
        'move_to_clean': 'move_tasks_resolution_history_to_clean',
        'upsert_clean_partition': 'upsert_tasks_resolution_history_partition'
    },
    sub_dag_func=incremental_clean_sub_dag,
)

workflows_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='incremental_load_raw_workflows',
    python_exec=exec_workflows_method,
    python_method={
        'extract_and_load_data': 'extract_and_load_data',
        'data_existence_check': 'data_existence_check',
        'upsert_partition': 'upsert_partition'
    },
    sub_dag_func=incremental_raw_sub_dag,
    provide_context=True
)

workflows_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='incremental_load_clean_workflows',
    python_exec=exec_workflows_method,
    python_method={
        'move_to_clean': 'move_to_clean',
        'upsert_clean_partition': 'upsert_partition'
    },
    sub_dag_func=incremental_clean_sub_dag,
    provide_context=True
)

clean_workflow_transitions_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='incremental_load_clean_workflow_transitions_table',
    python_exec=exec_workflows_method,
    python_method={
        'move_to_clean': 'move_workflow_transitions_to_clean',
        'upsert_clean_partition': 'upsert_workflow_transitions_partition'
    },
    sub_dag_func=incremental_clean_sub_dag,
    provide_context=True,
)

task_status_histories_raw_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='incremental_load_raw_task_status_histories',
    python_exec=exec_task_status_histories_method,
    python_method={
        'extract_and_load_data': 'extract_and_load_data',
        'data_existence_check': 'data_existence_check',
        'upsert_partition': 'upsert_partition'
    },
    sub_dag_func=incremental_raw_sub_dag,
    provide_context=True,
)

task_status_histories_clean_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='incremental_load_clean_task_status_histories',
    python_exec=exec_task_status_histories_method,
    python_method={
        'move_to_clean': 'move_to_clean',
        'upsert_clean_partition': 'upsert_partition'
    },
    sub_dag_func=incremental_clean_sub_dag,
    provide_context=True,
)

xcom_crm_load_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="XCom_crm_load",
    python_callable=xcom_crm_load,
    provide_context=True,
)

# flow
tasks_raw_sub_dag_task >> tasks_clean_sub_dag_task >> [clean_tasks_resolution_sub_dag_task,
                                                       clean_task_resolution_history_sub_dag_task]
workflows_raw_sub_dag_task >> workflows_clean_sub_dag_task >> clean_workflow_transitions_sub_dag_task

airflow_helpers.chain(
    task_status_histories_raw_sub_dag_task,
    task_status_histories_clean_sub_dag_task,
    clean_task_resolution_history_sub_dag_task
)

xcom_crm_load_task.set_upstream([clean_tasks_resolution_sub_dag_task,
                                 clean_workflow_transitions_sub_dag_task,
                                 workgroups_sub_dag_task,
                                 task_titles_sub_dag_task])

# TODO: add unit tests
