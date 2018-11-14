import json
from datetime import datetime, timedelta

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.load_ebdb_into_datalake import EBDBDatalake

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
EBDB_PRIORITY_TABLES = json.loads(env.get_airflow_env_var('EBDB_PRIORITY_TABLES'))
config_json = json.loads(env.get_airflow_env_var('ebdb_to_datalake'))


def create_raw_external_tables():
    ebdb_datalake = EBDBDatalake(bucket)
    table_names = ebdb_datalake.get_table_names()

    ebdb_datalake.create_raw_external_tables(table_names)


def move_ebdb_to_datalake(**kwargs):
    ebdb_datalake = EBDBDatalake(bucket, kwargs['execution_date'])
    table_names = ebdb_datalake.get_table_names(priority_tables=EBDB_PRIORITY_TABLES)

    for table_name in table_names:
        ebdb_datalake.move_to_datalake(table_name[0])


# def transform_to_clean():
#     EBDBDatalake(bucket).transform_tables_to_clean(config_json['clean_tables'])


# dag definition
dag = DAG(
    dag_id='bi-ebdb-to-datalake',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 5, 25, 0, 0, 0),
    schedule_interval='0 4 * * *',
    max_active_runs=1
)

# operators
move = BaseDAG.build_quintoandar_python_operator(
    task_id='move_ebdb_to_datalake',
    provide_context=True,
    python_callable=move_ebdb_to_datalake,
    dag=dag,
    execution_timeout=timedelta(hours=10)
)

create_raw = BaseDAG.build_quintoandar_python_operator(
    task_id='create_raw_external_tables',
    python_callable=create_raw_external_tables,
    dag=dag
)

# move_to_clean = PythonOperator(
#     task_id='transform_to_clean',
#     python_callable=transform_to_clean,
#     dag=dag
# )

# flow
move >> create_raw  # >> move_to_clean
