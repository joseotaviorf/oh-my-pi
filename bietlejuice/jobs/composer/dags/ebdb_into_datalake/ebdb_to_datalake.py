from datetime import datetime

from airflow.contrib.operators.databricks_operator import DatabricksSubmitRunOperator
from airflow.models import DAG

from bietlejuice.jobs.base import BaseDAG

cluster_id = '0511-125545-good204'

dag = DAG(
    dag_id='bi-ebdb-to-datalake',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 5, 25, 0, 0, 0),
    schedule_interval='0 4 * * *',
    max_active_runs=1,
    catchup=False
)

copy_ebdb_into_datalake_task = DatabricksSubmitRunOperator(
    task_id='copy_ebdb_into_datalake',
    dag=dag,
    provide_context=True,
    json={
        'existing_cluster_id': cluster_id,
        'spark_python_task': {
            'python_file': 'dbfs:/FileStore/airflow/bla.py',
            'parameters': ['Adan']
        }
    }
)
