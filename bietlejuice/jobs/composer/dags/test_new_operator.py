from datetime import datetime

from airflow.models import DAG
from airflow.operators.quintoandar_utils import MySqlToS3Operator

from bietlejuice.jobs.composer.base.airflow import BaseDAG

DAG_ID = "test_new_operator"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2019, 8, 1, 0, 0, 0),
    schedule_interval="0 4 * * *",
    max_active_runs=1,
    catchup=False,
)

dump_dag_table_task = MySqlToS3Operator(
    dag=dag,
    sql='select * from dag',
    task_id="dump_dag_table_task",
    bucket='5a-datalake-forno',
    filename='data.json',
    s3_file_path='raw/test_operator/dag',
    mysql_conn_id='airflow_db',
    gzip=True
)

dump_dag_run_table_task = MySqlToS3Operator(
    dag=dag,
    sql='select * from dag_run',
    task_id="dump_dag_run_table_task",
    bucket='5a-datalake-forno',
    filename='data.json',
    s3_file_path='raw/test_operator/dag_run',
    mysql_conn_id='airflow_db',
    gzip=True
)

dump_task_fail_table_task = MySqlToS3Operator(
    dag=dag,
    sql='select * from task_fail',
    task_id="dump_task_fail_table_task",
    bucket='5a-datalake-forno',
    filename='data.json',
    s3_file_path='raw/test_operator/task_fail',
    mysql_conn_id='airflow_db',
    gzip=True
)
