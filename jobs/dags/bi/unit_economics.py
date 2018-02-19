from datetime import datetime, timedelta
from airflow.models import DAG
from jobs.dags.util import environment as env
from airflow.operators.quintoandar import QuintoAndarPythonOperator
from jobs.base.base_etl import BaseETL, EnumDb
from jobs.new_etl.dim_utils import load_dim_from_ods_to_dw

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')


def create_base_ticket_tbl(_bucket):
    table = BaseETL.from_db_query(
        db_enum=EnumDb.BI_ODS,
        query='select * from unit_economics.vw_base_ticket_task;'
    )

    table = BaseETL.decode_table(table, 'LATIN-1')
    BaseETL.bulk_insert(
        table=table,
        table_name='unit_economics.tbl_base_ticket_task',
        db_enum=EnumDb.BI_ODS,
        encoding='UTF8',
        append=False,
        commit=True,
        bucket_name='{}/raw/ods/base_ticket_task'.format(_bucket)
    )

# create DAG definition
dag = DAG(
    dag_id='bi-load-property-economics',
    default_args={
        'owner': 'Data team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 17, 0, 0, 0),
    schedule_interval='@daily',
    max_active_runs=1
)

ticket_base_tbl = QuintoAndarPythonOperator(
    dag=dag,
    task_id='ticket_base_tbl',
    execution_timeout=timedelta(hours=3),
    python_callable=create_base_ticket_tbl,
    op_kwargs={'_bucket': bucket}
)

fact_property_economics = QuintoAndarPythonOperator(
    dag=dag,
    task_id='etl_fact_property_economics',
    execution_timeout=timedelta(hours=3),
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'fact_property_economics', 'bucket': bucket, 'insert_dummy': False}
)

ticket_base_tbl >> fact_property_economics
