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

check_s3_objects_task = S3KeySensor(
    task_id="check-s3-objects",
    poke_interval=3*60,
    timeout=10*60,
    aws_conn_id="aws_default",
    bucket_name='5a-datalake-forno',
    bucket_key="teste/bietlejuice/dag_teste",
    dag=dag
)

t3 = DummyOperator(
    task_id='random_task',
    dag=dag
)


t1.set_downstream(check_s3_objects_task)
check_s3_objects_task.set_downstream(t3)
