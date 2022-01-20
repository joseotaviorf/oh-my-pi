from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.dummy_operator import DummyOperator
from airflow.operators.sensors import S3KeySensor
from airflow.utils.dates import days_ago


default_args = {
    'owner': 'airflow',
    'start_date': days_ago(1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'execution_timeout': timedelta(hours=3),
    'depends_on_past': False
    }

dag = DAG(
    'composer_dependency_dag_test',
    start_date=days_ago(1),
    max_active_runs=1,
    schedule_interval='* 8 * * *',
    default_args=default_args,
    catchup=False
    )

t1 = DummyOperator(
    task_id='pre-task',
    dag=dag
)

first_dep = S3KeySensor(
    task_id="first_dep",
    poke_interval=3*60,
    timeout=2*60*60,
    aws_conn_id="aws_default",
    bucket_name='5a-datalake-prod',
    bucket_key="dags_execution_logs/2022-01-20/bietlejuice.enrich_ebdb_agents.SUCCESS",
    dag=dag
)

second_dep = S3KeySensor(
    task_id="second_dep",
    poke_interval=3*60,
    timeout=2*60*60,
    aws_conn_id="aws_default",
    bucket_name='5a-datalake-prod',
    bucket_key="dags_execution_logs/2022-01-20/bietlejuice.docx.SUCCESS",
    dag=dag
)

t3 = DummyOperator(
    task_id='random_task',
    dag=dag
)

t1 >> [first_dep,second_dep] >> t3