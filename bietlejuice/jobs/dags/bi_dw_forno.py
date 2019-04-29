import json
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.wrappers.Redshift import Redshift
from qa_python_utils import QuintoAndarLogger

DW_PROD_ID = env.get_airflow_env_var('DW_PROD_ID')
DW_FORNO_ID = env.get_airflow_env_var('DW_FORNO_ID')
DW_FORNO_CONFIGS = json.loads(env.get_airflow_env_var('DW_FORNO_CONFIGS'))

# global vars
logger = QuintoAndarLogger('dw_forno')
MAIN_DAG_ID = 'bi-dw_forno'
MAIN_START_DATE = datetime(2019, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 0 * * 1')


def shutdown_cluster(target_cluster):
    rs_client = Redshift()
    # if there is no cluster with given id, do not tries to shutdown
    if rs_client.check_if_cluster_exists(cluster_id=target_cluster):
        rs_client.shutdown_cluster(cluster_id=target_cluster)


def check_cluster_shutdown(target_cluster):
    rs_client = Redshift()
    rs_client.wait_for_cluster_shutdown(cluster_id=target_cluster)


def create_cluster(source_cluster, target_cluster, config_json):
    rs_client = Redshift()
    rs_client.create_cluster_from_snapshot(source_cluster_id=source_cluster, target_cluster_id=target_cluster,
                                           config_json=config_json)


def check_cluster_availability(target_cluster):
    rs_client = Redshift()
    rs_client.wait_for_cluster_availability(cluster_id=target_cluster)


def scale_down_cluster(target_cluster):
    rs_client = Redshift()
    rs_client.scale_down_cluster(cluster_id=target_cluster)


dag = DAG(
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

shutdown_cluster_cluster_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='shutdown_cluster',
    python_callable=shutdown_cluster,
    op_kwargs={'target_cluster': DW_FORNO_ID}
)

check_cluster_shutdown_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='check_cluster_shutdown',
    python_callable=check_cluster_shutdown,
    op_kwargs={'target_cluster': DW_FORNO_ID}
)

create_cluster_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='create_cluster',
    python_callable=create_cluster,
    op_kwargs={'source_cluster': DW_PROD_ID,
               'target_cluster': DW_FORNO_ID,
               'config_json': DW_FORNO_CONFIGS}
)

check_cluster_availability_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='check_cluster_availability',
    python_callable=check_cluster_availability,
    op_kwargs={'target_cluster': DW_FORNO_ID}
)

scale_down_cluster_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='scale_down_cluster',
    python_callable=scale_down_cluster,
    op_kwargs={'target_cluster': DW_FORNO_ID}
)

check_cluster_scaled_down_availability_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='check_cluster_scaled_down_availability',
    python_callable=check_cluster_availability,
    op_kwargs={'target_cluster': DW_FORNO_ID}
)

# Tasks Flow
airflow_helpers.chain(shutdown_cluster_cluster_task, check_cluster_shutdown_task, create_cluster_task,
                      check_cluster_availability_task, scale_down_cluster_task,
                      check_cluster_scaled_down_availability_task)
