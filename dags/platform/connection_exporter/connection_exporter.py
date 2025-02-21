from airflow import DAG
from airflow.hooks.base_hook import BaseHook
from airflow.hooks.S3_hook import S3Hook
from airflow.operators.python_operator import PythonOperator
import json
import csv
import os
from datetime import datetime
from airflow import settings
from airflow.models.connection import Connection


dag = DAG(
    'export_connections_to_s3',
    description='A DAG to list all connections and export to S3',
    schedule_interval=None,
    start_date=datetime(2025, 2, 21),
    catchup=False,
)

def list_connection_ids(**context):
    session = settings.Session()
    return session.query(Connection).all()

def list_connections():
    connections = list_connection_ids()
    
    connection_data = []

    for conn in connections:
        connection_info = {
            'conn_id': conn.conn_id,
            'conn_type': conn.conn_type,
            'host': conn.host,
            'schema': conn.schema,
            'login': conn.login,
            'password': conn.password,
            'port': conn.port,
            'extra': conn.extra,
        }
        connection_data.append(connection_info)
    
    return connection_data

def export_connections_to_json():
    connections = list_connections()
    file_path = '/tmp/airflow_connections.json'
    
    with open(file_path, 'w') as f:
        json.dump(connections, f, indent=4)
    
    return file_path

def upload_to_s3(file_path, bucket_name, s3_key):
    s3_hook = S3Hook(aws_conn_id='aws_default')
    s3_hook.load_file(filename=file_path, key=s3_key, bucket_name=bucket_name, replace=True)
    os.remove(file_path)

def export_and_upload_to_s3():
    file_path = export_connections_to_json()
    bucket_name = '5a-datalake-prod'
    s3_key = 'airflow_connections/airflow_connections.json'
    
    upload_to_s3(file_path, bucket_name, s3_key)

export_task = PythonOperator(
    task_id='export_connections_to_s3',
    python_callable=export_and_upload_to_s3,
    dag=dag,
)
