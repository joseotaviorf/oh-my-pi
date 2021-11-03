import logging
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.new_base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags import DW_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from bietlejuice.jobs.etl.crm.tasks import CRMTasksFactory, CRMTasksTableEnum

# env vars
env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
S3_BUCKET = env.get_airflow_env_var('bi-datalake-s3-bucket')
MONGO_CLIENT_URI = env.get_airflow_env_var('MONGODB_CRM_URI')

MAIN_DAG_ID = 'bi-crm-dw'
MAIN_START_DATE = datetime(2018, 1, 1)
MAIN_SCHEDULE_INTERVAL = None  # will get triggered by bi-supply-demand-etl


# functions
def exec_factory_method(class_, method, **kwargs):
    crm_tasks = CRMTasksFactory.factory(
        class_=class_,
        s3_bucket=S3_BUCKET,
        mongo_client_uri=MONGO_CLIENT_URI,
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


def class_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    move_dim_to_staging_task = BaseDAG.build_python_operator(
        task_id='move_dim_to_staging',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'move_dim_to_staging'
        }
    )

    move_fact_to_staging_task = BaseDAG.build_python_operator(
        task_id='move_fact_to_staging',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'move_fact_to_staging'
        }
    )

    append_dim_to_dw_task = BaseDAG.build_python_operator(
        task_id='append_dim_to_dw',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'append_dim_to_dw'
        }
    )

    append_fact_to_dw_task = BaseDAG.build_python_operator(
        task_id='append_fact_to_dw',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'append_fact_to_dw'
        }
    )

    delete_staging_fact_entries_task = BaseDAG.build_python_operator(
        task_id='delete_staging_fact_entries',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'delete_staging_fact_entries'
        }
    )

    delete_staging_dim_entries_task = BaseDAG.build_python_operator(
        task_id='delete_staging_dim_entries',
        python_callable=exec_factory_method,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': kwargs['class_'],
            'method': 'delete_staging_dim_entries'
        }
    )

    airflow_helpers.chain(
        move_dim_to_staging_task,
        append_dim_to_dw_task,
        delete_staging_dim_entries_task
    )

    airflow_helpers.chain(
        move_fact_to_staging_task,
        append_fact_to_dw_task,
        delete_staging_fact_entries_task
    )

    return local_dag


def xcom_dependencies(task_id, dag_id, **kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    for t_id, d_id in zip(task_id, dag_id):
        status = xcom.xcom_pull(task_instance=kwargs['ti'], key=exec_date, task_id=t_id, dag_id=d_id)
        if not status:
            raise ValueError('For {}, the process {}:{} have not finished yet'.format(exec_date, d_id, t_id))
        else:
            logging.info('REQUIREMENT MET. For {}, the process {}:{} have finished'.format(exec_date, d_id, t_id))

    logging.info('All Requirements met')


# operators
# check the DAG dependencies
xcom_dependencies_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='XCom_dependencies',
    provide_context=True,
    python_callable=xcom_dependencies,
    op_kwargs={'task_id': ['XCom_fact_listing_rent_flows', 'XCom_crm_load'],
               'dag_id': ['bi-supply-demand-etl', 'bi-crm-load']}
)

tasks_credit_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_credit',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.CREDIT
)

tasks_photo_job_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_photo_job',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.PHOTO_JOB
)

tasks_visit_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_visit',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.VISIT,
    has_bridge=True
)

tasks_closing_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_closing',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.CLOSING
)

tasks_onboarding_tenant_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_onboarding_tenant',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.ONBOARDING_TENANT
)

tasks_payment_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_payment',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.PAYMENT
)

tasks_lead_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_lead',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.LEAD
)

tasks_inspection_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_inspection',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.INSPECTION
)

tasks_repair_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_repair',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.REPAIR
)

tasks_ungrouped_manual_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_ungrouped_manual',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.UNGROUPED_MANUAL
)

tasks_offboarding_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_offboarding',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.OFFBOARDING
)

tasks_linhadireta_chat_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_linhadireta_chat',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.LINHADIRETA_CHAT
)

tasks_collection_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='tasks_collection',
    sub_dag_func=class_sub_dag,
    class_=CRMTasksTableEnum.COLLECTION
)

fact_lead_tasks_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='fact_lead_tasks',
    python_callable=BaseETL.move_file_query_data_to_db,
    op_kwargs={'schema': 'crm_20211103',
               'file_name': '{}/crm/fact_lead_tasks.sql'.format(DW_QUERIES_DIR),
               'append': False,
               'db_enum_source': EnumDB.BI_DW,
               'db_enum_destination': EnumDB.BI_DW,
               'table_name': 'fact_lead_tasks'
               }
)


# flow
dw_crm_subdags = [
    tasks_credit_sub_dag_task,
    tasks_photo_job_sub_dag_task,
    tasks_visit_sub_dag_task,
    tasks_closing_sub_dag_task,
    tasks_onboarding_tenant_sub_dag_task,
    tasks_payment_sub_dag_task,
    tasks_inspection_sub_dag_task,
    tasks_repair_sub_dag_task,
    tasks_ungrouped_manual_sub_dag_task,
    tasks_offboarding_sub_dag_task,
    tasks_linhadireta_chat_sub_dag_task,
    tasks_collection_sub_dag_task,
    tasks_lead_sub_dag_task
]

xcom_dependencies_task.set_downstream(dw_crm_subdags)

tasks_lead_sub_dag_task.set_downstream(fact_lead_tasks_task)

# TODO: add unit tests
