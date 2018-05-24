import json
from datetime import datetime, timedelta

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.load_ebdb_into_datalake import EBDBDatalake

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
config_json = json.loads(env.get_airflow_env_var('ebdb_to_datalake'))
owner = 'Data Team'

ebdb_datalake = EBDBDatalake(config_json['schema_name'], bucket)
table_names = ebdb_datalake.get_table_names()


def move_ebdb_to_datalake():
    for table_name in table_names:
        ebdb_datalake.move_to_datalake(table_name[0])


def create_raw_external_tables():
    # conversions = ebdb_datalake.get_type_conversion_dict()
    ddl_suffix = """) row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
                                 with serdeproperties (
                                   'separatorChar' = ',',
                                   'quoteChar' = '\"'
                                 )
                                stored as textfile
                                location 's3://{}/raw/{}/{}/'"""
    for table_name in table_names:
        ebdb_datalake.create_external_table(table_name[0], ddl_suffix)


def transform_to_clean():
    ddl_suffix = """) stored as parquet
                                location 's3://{}/clean/{}/{}/'"""
    ebdb_datalake.transform_tables_to_clean(config_json['clean_table_infos'], ddl_suffix)


move = PythonOperator(
    task_id='move_ebdb_to_datalake',
    owner=owner,
    python_callable=move_ebdb_to_datalake
)

create_raw = PythonOperator(
    task_id='create_raw_external_tables',
    owner=owner,
    python_callable=create_raw_external_tables
)

move_to_clean = PythonOperator(
    task_id='transform_to_clean',
    owner=owner,
    python_callable=transform_to_clean
)

with DAG(
        dag_id='bi-elt-ebdb-to-datalake',
        default_args={
            'owner': owner,
            'wait_for_downstream': False,
            'depends_on_past': False
        },
        start_date=datetime(2018, 1, 1, 0, 0, 0),
        schedule_interval=timedelta(hours=8),
        max_active_runs=1
) as dag:
    dag >> move >> create_raw >> move_to_clean
