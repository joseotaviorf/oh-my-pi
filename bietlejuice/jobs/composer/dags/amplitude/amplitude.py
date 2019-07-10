from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (QuintoAndarDatabricksCreateClusterOperator,
                                                      QuintoAndarDatabricksTerminateClusterOperator,
                                                      QuintoAndarDatabricksSubmitRunOperator)

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base import BaseDAG

logger = QuintoAndarLogger('amplitude')

DAG_ID = 'amplitude'
S3_PREFIX = Variable.get('databricks_bietlejuice_s3_prefix')
LOAD_EVENTS_INTO_DATALAKE_RAW_FILE_PATH = S3_PREFIX \
    + '/spark_jobs/forno/amplitude/load_events_into_datalake_raw.py'
LOGS_OUTPUT_PATH = S3_PREFIX + '/logs/' + DAG_ID

CLUSTER_DESCRIPTION = Variable.get('databricks_memory_optimized_cluster', deserialize_json=True)
CLUSTER_DESCRIPTION['cluster_name'] = DAG_ID + '_' + '{{ run_id }}'
CLUSTER_DESCRIPTION['cluster_log_conf']['s3']['destination'] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get('bietlejuice_default_libraries', deserialize_json=True)
logger = QuintoAndarLogger('AmplitudeEvents')

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2019, 5, 31, 0, 0, 0),
    schedule_interval='30 3 * * *',
    max_active_runs=1,
    catchup=False
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id='create_cluster',
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION
)

events_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id='events_to_datalake_raw',
    dag=dag,
    json={
        'existing_cluster_id': '{{task_instance.xcom_pull(task_ids="create_cluster", key="cluster_id")}}',
        'spark_python_task': {
            'python_file': LOAD_EVENTS_INTO_DATALAKE_RAW_FILE_PATH,
            'parameters': ['{{ ds }}']
        }
    }
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag,
    task_id='terminate_cluster'
)

airflow_helpers.chain(create_cluster_task,
                      events_to_datalake_raw_task,
                      terminate_cluster_task)
