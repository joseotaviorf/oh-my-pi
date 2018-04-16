import os
from datetime import datetime
from datetime import timedelta
import petl
from airflow.models import DAG
from bietlejuice.jobs.dags.util import environment as env
from airflow.operators.quintoandar import QuintoAndarPythonOperator
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_etl import EnumDb
from bietlejuice.jobs.wrappers.GoogleDrive.google_drive_api import GoogleDriveApi

table_name = 'employee_base'
env.set_airflow_var_to_local_env(
    'ANALYTICS_KEY_JSON',
    'BI_DW',
    'AWS_SECRET_ACCESS_KEY',
    'AWS_ACCESS_KEY_ID',
    'AWS_DEFAULT_REGION'
)
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')


def extract_transform_employee_data():
    """
    Reads Google Drive Sheets and extracts updated data from there
    Sheets name = 'Base Centro de Custo'
    Updated by marina.machado@quintoandar.com.br
    :return: employee_base table
    """
    name = 'Base Centro de Custo'
    # Extract
    file_name, file_path_destination = GoogleDriveApi().download_file(
        file_name=name,
        file_path_destination='/tmp',
        file_name_destination=name + '.xlsx'
    )
    table = []
    if file_name and file_path_destination:
        file_name = '{}/{}'.format(file_path_destination, file_name)
        sheet = petl\
            .fromxlsx(filename=file_name,
                      sheet='QuintoAndar')\
            .cut(['Nome', 'Centro de custo'])
        # Transform
        # added date for traceability
        for i, record in enumerate(sheet):
            if i == 0:
                table.append([record[0], record[1], 'Data'])
            elif record[1] is not None:
                table.append([record[0], record[1], datetime.now().date()])
    return table


def load_employee_base_data(_table_name, _bucket):
    # Extract and Transform data
    _table = extract_transform_employee_data()
    # Load
    BaseETL.bulk_insert(
        table=_table,
        table_name='growth.{}'.format(_table_name),
        db_enum=EnumDb.BI_DW,
        encoding='UTF8',
        append=True,
        commit=True,
        bucket_name='{}/raw/growth/{}'.format(_bucket, _table_name)
    )


# TODO: Implement this when Growth Model structure is finished
def load_employee_growth_data():
    # Select Grouped categories by Date and insert Counts in Growth Model
    pass


# create DAG definition
dag = DAG(
    dag_id='bi-growth-employees',
    description='ETL Pipeline for collecting updated employees categories and grouping it for growth model',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 4, 0, 0, 0),
    schedule_interval='@weekly',
    max_active_runs=1
)

employee_base = QuintoAndarPythonOperator(
    dag=dag,
    task_id='etl_employee_base_data',
    execution_timeout=timedelta(hours=3),
    python_callable=load_employee_base_data,
    op_kwargs={'_table_name': table_name, '_bucket': bucket}
)

employee_growth = QuintoAndarPythonOperator(
    dag=dag,
    task_id='etl_employee_growth_data',
    execution_timeout=timedelta(hours=3),
    python_callable=load_employee_growth_data
)

# flow
employee_base >> employee_growth
