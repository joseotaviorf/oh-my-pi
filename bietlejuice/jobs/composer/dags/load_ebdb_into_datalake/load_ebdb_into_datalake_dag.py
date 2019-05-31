from datetime import datetime

from airflow.contrib.operators.databricks_operator import DatabricksSubmitRunOperator
from airflow.operators.python_operator import BranchPythonOperator
from airflow.models import DAG

from bietlejuice.jobs.base import BaseDAG
from bietlejuice.jobs.composer.etl.load_ebdb_into_datalake import load_ebdb_into_datalake_etl

DAG_ID = 'load-ebdb-into-datalake'
ebdb_raw_file_path = 'dbfs:/FileStore/airflow/bla.py'
create_athena_external_tables_file_path = 'dbfs:/FileStore/airflow/bla.py'

new_cluster = {
    'cluster_name': DAG_ID,
    'spark_version': '2.1.0-db3-scala2.11',
    'node_type_id': 'i3.xlarge',
    'aws_attributes': {
        'availability': 'SPOT',
        'spot_bid_price_percent': 100,
        'zone_id': 'us-east-1'
    },
    'num_workers': 2
}

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2019, 6, 1, 0, 0, 0),
    schedule_interval='0 4 * * *',
    max_active_runs=1,
    catchup=False
)


def check_if_ebdb_exists():
    client = load_ebdb_into_datalake_etl.get_athena_client()
    execution_id = load_ebdb_into_datalake_etl.execute_athena_query(client, 'show tables in ebdb', 'ebdb')
    results = client.get_query_results(QueryExecutionId=execution_id, MaxResults=1000)
    ebdb_exists = 'ebdb' in [row['Data'][0]['VarCharValue'] for row in results['ResultSet']['Rows']]
    if ebdb_exists:
        return 'ebdb_raw_daily'
    else:
        return 'ebdb_raw_first_time'


check_if_ebdb_exists = BranchPythonOperator(task_id='check_if_ebdb_exists', python_callable=check_if_ebdb_exists)

ebdb_raw_first_time = DatabricksSubmitRunOperator(
    task_id='ebdb_raw_first_time',
    dag=dag,
    provide_context=True,
    json={
        'new_cluster': new_cluster,
        'spark_python_task': {
            'python_file': ebdb_raw_file_path,
            'parameters': [
                'first_time'
            ]
        }
    }
)

ebdb_raw_daily = DatabricksSubmitRunOperator(
    task_id='ebdb_raw_daily',
    dag=dag,
    provide_context=True,
    json={
        'new_cluster': new_cluster,
        'spark_python_task': {
            'python_file': ebdb_raw_file_path,
            'parameters': [
                'daily'
            ]
        }
    }
)

create_athena_external_tables = DatabricksSubmitRunOperator(
    task_id='create_athena_external_tables',
    dag=dag,
    provide_context=True,
    json={
        'new_cluster': new_cluster,
        'spark_python_task': {
            'python_file': create_athena_external_tables_file_path
        }
    }
)

# dependencies
check_if_ebdb_exists >> ebdb_raw_first_time >> create_athena_external_tables
check_if_ebdb_exists >> ebdb_raw_daily >> create_athena_external_tables
