import json
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.contrib.operators.databricks_operator import DatabricksSubmitRunOperator
from airflow.hooks.base_hook import BaseHook
from airflow.models import DAG
from databricks import DatabricksClusterClient, DatabricksLibraryClient
from python_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base import BaseDAG

logger = QuintoAndarLogger('load_ebdb_into_datalake')

DAG_ID = 'load-ebdb-into-datalake'
S3_PREFIX = 's3://5a-databricks/github-repos/bi-etl-ejuice'

LOAD_EBDB_INTO_DATALAKE_RAW_FILE_PATH = S3_PREFIX + '/spark_jobs/\
load-ebdb-into-datalake/load_ebdb_into_datalake.py'
CREATE_RAW_EXTERNAL_TABLES_FILE_PATH = S3_PREFIX + '/spark_jobs/\
load-ebdb-into-datalake/create_raw_external_tables.py'

LOGS_OUTPUT_PATH = S3_PREFIX + '/logs/load-ebdb-into-datalake'

CLUSTER_DESCRIPTION = {
    'autoscale': {
        'min_workers': 3,
        'max_workers': 4
    },
    'cluster_name': DAG_ID,
    'spark_version': '5.4.x-scala2.11',
    'spark_conf': {
        'spark.speculation': 'true'
    },
    'aws_attributes': {
        'first_on_demand': 1,
        'availability': 'SPOT_WITH_FALLBACK',
        'zone_id': 'us-east-1e',
        'instance_profile_arn': 'arn:aws:iam::632540934959:instance-profile/Databricks',
        'spot_bid_price_percent': 100,
        'ebs_volume_count': 0
    },
    'node_type_id': 'i3.xlarge',
    'driver_node_type_id': 'i3.xlarge',
    'ssh_public_keys': [],
    'custom_tags': {},
    'spark_env_vars': {
        'PYSPARK_PYTHON': '/databricks/python3/bin/python3'
    },
    'autotermination_minutes': 60,
    'enable_elastic_disk': True,
    'cluster_source': 'API',
    'init_scripts': [],
    'cluster_log_conf': {
        's3': {
            'destination': LOGS_OUTPUT_PATH,
            'region': 'us-east-1'
        }
    }
}

LIBRARIES_DESCRIPTION = [
    {
        'whl': 's3://5a-databricks/github-repos/bi-etl-ejuice/libraries/bi_etl_ejuice-0.1.0-py3-none-any.whl'
    },
    {
        'whl': 's3://5a-databricks/github-repos/bi-etl-ejuice/libraries/python_logger-0.1.0-py3-none-any.whl'
    },
    {
        'jar': 's3://5a-databricks/github-repos/bi-etl-ejuice/libraries/mysql-connector-java-5.1.47.jar'
    }
]


@logger
def create_cluster():
    dbricks_connection = BaseHook.get_connection('databricks_default')
    dbricks_host = dbricks_connection.host
    dbricks_token = json.loads(dbricks_connection.extra)['token']

    cluster_client = DatabricksClusterClient(dbricks_host, dbricks_token)
    cluster_id = cluster_client.create_cluster(CLUSTER_DESCRIPTION)

    libraries_client = DatabricksLibraryClient(dbricks_host, dbricks_token)
    libraries_client.install_libraries(cluster_id, LIBRARIES_DESCRIPTION)

    return cluster_id


@logger
def terminate_cluster(**kwargs):
    dbricks_connection = BaseHook.get_connection('databricks_default')
    dbricks_host = dbricks_connection.host
    dbricks_token = json.loads(dbricks_connection.extra)['token']
    cluster_client = DatabricksClusterClient(dbricks_host, dbricks_token)
    cluster_id = kwargs['ti'].xcom_pull(task_ids='create_cluster')
    cluster_client.permanent_delete_cluster(cluster_id)


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2019, 5, 31, 0, 0, 0),
    schedule_interval='0 4 * * *',
    max_active_runs=1,
    catchup=False
)

create_cluster_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='create_cluster',
    python_callable=create_cluster
)

ebdb_to_datalake_raw_task = DatabricksSubmitRunOperator(
    task_id='ebdb_to_datalake_raw',
    dag=dag,
    json={
        'existing_cluster_id': '{{task_instance.xcom_pull(task_ids="create_cluster")}}',
        'spark_python_task': {
            'python_file': LOAD_EBDB_INTO_DATALAKE_RAW_FILE_PATH
        }
    }
)

create_raw_external_tables_task = DatabricksSubmitRunOperator(
    task_id='create_raw_external_tables',
    dag=dag,
    json={
        'existing_cluster_id': '{{task_instance.xcom_pull(task_ids="create_cluster")}}',
        'spark_python_task': {
            'python_file': CREATE_RAW_EXTERNAL_TABLES_FILE_PATH
        }
    }
)

terminate_cluster_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='terminate_cluster',
    provide_context=True,
    python_callable=terminate_cluster
)

airflow_helpers.chain(create_cluster_task,
                      ebdb_to_datalake_raw_task,
                      create_raw_external_tables_task,
                      terminate_cluster_task)
