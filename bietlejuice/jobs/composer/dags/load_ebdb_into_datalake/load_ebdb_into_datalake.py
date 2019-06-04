from datetime import datetime

from airflow.contrib.operators.databricks_operator import DatabricksSubmitRunOperator
from airflow.models import DAG

import bietlejuice.jobs.composer.etl.load_ebdb_into_datalake as load_ebdb_into_datalake_etl
from bietlejuice.jobs.base import BaseDAG
from bietlejuice.jobs.composer.etl.load_ebdb_into_datalake import EBDBIntoDatalakeLoader

DAG_ID = 'load-ebdb-into-datalake'
load_ebdb_into_datalake_raw_file_path = 'dbfs:/FileStore/airflow/load_ebdb_into_datalake/load_ebdb_into_datalake.py'
create_raw_external_tables_file_path = 'dbfs:/FileStore/airflow/load_ebdb_into_datalake/create_raw_external_tables.py'

cluster_id_test = '0511-125545-good204'

new_cluster = {
    'spark_version': '5.3.x-scala2.11',
    'node_type_id': 'i3.xlarge',
    'aws_attributes': {
        'availability': 'SPOT',
        'spot_bid_price_percent': 100,
        'zone_id': 'us-east-1'
    },
    'num_workers': 2
}


def get_task_to_load_ebdb_data_into_datalake():
    athena_client = load_ebdb_into_datalake_etl.get_athena_client()
    execution_id = load_ebdb_into_datalake_etl.execute_athena_query(athena_client, 'show databases', 'default')
    results = athena_client.get_query_results(QueryExecutionId=execution_id, MaxResults=1000)
    if EBDBIntoDatalakeLoader.ATHENA_RAW_SCHEMA in [row['Data'][0]['VarCharValue'] for row in
                                                    results['ResultSet']['Rows']]:
        return 'ebdb_to_datalake_raw_daily'
    else:
        return 'ebdb_to_datalake_raw_first_time'


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

_ebdb_to_datalake_raw_first_time = DatabricksSubmitRunOperator(
    task_id='ebdb_to_datalake_raw_first_time',
    dag=dag,
    json={
        # 'new_cluster': new_cluster,
        'existing_cluster_id': cluster_id_test,
        'spark_python_task': {
            'python_file': load_ebdb_into_datalake_raw_file_path
        }
    }
)

_create_athena_raw_external_tables = DatabricksSubmitRunOperator(
    task_id='create_athena_raw_external_tables',
    dag=dag,
    json={
        # 'new_cluster': new_cluster,
        'existing_cluster_id': cluster_id_test,
        'spark_python_task': {
            'python_file': create_raw_external_tables_file_path
        }
    }
)

_ebdb_to_datalake_raw_first_time >> _create_athena_raw_external_tables
