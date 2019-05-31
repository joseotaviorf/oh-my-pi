from datetime import datetime

from airflow.contrib.operators.databricks_operator import DatabricksSubmitRunOperator
from airflow.models import DAG

from bietlejuice.jobs.base import BaseDAG

DAG_ID = 'load-ebdb-into-datalake'

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

load_ebdb_into_datalake_raw_task = DatabricksSubmitRunOperator(
    task_id='load_ebdb_into_datalake_raw_task',
    dag=dag,
    json={
        'new_cluster': new_cluster,
        'spark_python_task': {
            'python_file': 'dbfs:/FileStore/airflow/bla.py',
            'parameters': ['first_time', '{{ ds }}']
        }
    }
)
