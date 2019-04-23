import json
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.contrib.operators.emr_add_steps_operator import EmrAddStepsOperator
from airflow.contrib.operators.emr_create_job_flow_operator import EmrCreateJobFlowOperator
from airflow.contrib.operators.emr_terminate_job_flow_operator import EmrTerminateJobFlowOperator
from airflow.contrib.sensors.emr_step_sensor import EmrStepSensor
from airflow.models import DAG
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.sensors import QuintoAndarEmrJobFlowSensor

# global vars
MAIN_DAG_ID = 'bi-agents-allocation-optimization'
MAIN_START_DATE = datetime(2019, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 8 * * *')

# env vars
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
bi_hekima_json = json.loads(env.get_airflow_env_var('bi-agents-allocation-optimization')
                            .replace('__S3_BUCKET__', s3_bucket))


# functions
def add_new_table_partition(ds, **kwargs):
    athena_client = AthenaClient(s3_bucket)
    athena_client.upsert_single_partition(
        bucket_folder_path='{}/hekima/optimization_result/historical'.format(s3_bucket),
        database='datalake_raw',
        table='agents_allocation_optimization',
        partition_name='dt_predicted',
        partition_value=ds
    )


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


def create_job_flow_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    create_job_flow_task = EmrCreateJobFlowOperator(
        task_id='create_job_flow',
        job_flow_overrides=bi_hekima_json['job_flow_overrides'],
        dag=local_dag
    )

    create_job_flow_sensor = QuintoAndarEmrJobFlowSensor(
        task_id='check_create_job_flow',
        job_flow_id="{{ task_instance.xcom_pull('create_job_flow', key='return_value') }}",
        dag=local_dag
    )

    create_job_flow_task >> create_job_flow_sensor

    return local_dag


def send_step_sub_dag(sub_dag_name, step, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    step_task = EmrAddStepsOperator(
        task_id='{}_step'.format(step),
        job_flow_id="{{ task_instance.xcom_pull('create_job_flow', key='return_value') }}",
        steps=bi_hekima_json['{}_params'.format(step)],
        dag=local_dag
    )

    step_sensor = EmrStepSensor(
        task_id='check_{}_step'.format(step),
        job_flow_id="{{ task_instance.xcom_pull('create_job_flow', key='return_value') }}",
        step_id="{{ task_instance.xcom_pull('{}_step', key='return_value')[0] }}".format(step),
        dag=local_dag
    )

    step_task >> step_sensor

    return local_dag


def terminate_job_flow_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    terminate_job_flow_task = EmrTerminateJobFlowOperator(
        task_id='terminate_job_flow',
        job_flow_id="{{ task_instance.xcom_pull('create_job_flow', key='return_value') }}",
        dag=local_dag
    )

    check_terminate_job_flow_sensor = QuintoAndarEmrJobFlowSensor(
        task_id='check_terminate_job_flow',
        job_flow_id="{{ task_instance.xcom_pull('create_job_flow', key='return_value') }}",
        dag=local_dag
    )

    terminate_job_flow_task >> check_terminate_job_flow_sensor

    return local_dag


# operators
create_job_flow_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='create_job_flow',
    sub_dag_func=create_job_flow_sub_dag
)

data_preparation_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='data_preparation_step',
    step='data_preparation',
    sub_dag_func=send_step_sub_dag
)

visits_learning_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='visits_learning_step',
    step='visits_learning',
    sub_dag_func=send_step_sub_dag
)

add_new_visits_table_partition_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='add_new_visits_table_partition',
    python_callable=add_new_table_partition,
    provide_context=True,
    op_kwargs={
        'schema': 'datalake_raw',
        'table_name': 'region_code_visits_prediction'
    }
)

agents_allocation_optimization_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='agents_allocation_optimization_step',
    step='agents_allocation_optimization',
    sub_dag_func=send_step_sub_dag
)

add_new_agents_table_partition_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='add_new_agents_table_partition',
    python_callable=add_new_table_partition,
    provide_context=True,
    op_kwargs={
        'schema': 'datalake_raw',
        'table_name': 'agents_allocation_optimization'
    }
)

terminate_job_flow_sub_dag_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='terminate_job_flow',
    sub_dag_func=terminate_job_flow_sub_dag
)

# flow
airflow_helpers.chain(
    create_job_flow_sub_dag_task,
    data_preparation_sub_dag_task,
    visits_learning_sub_dag_task,
    agents_allocation_optimization_sub_dag_task
)

visits_learning_sub_dag_task >> add_new_agents_table_partition_task
agents_allocation_optimization_sub_dag_task.set_downstream([add_new_agents_table_partition_task,
                                                            terminate_job_flow_sub_dag_task])
