from datetime import datetime

from airflow import DAG
from airflow.operators.quintoandar import QuintoAndarPythonOperator
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from bietlejuice.jobs.dags import DW_STAGING_QUERIES_DIR, DATALAKE_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env

env.set_airflow_var_to_local_env('BI_DW')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
athena = AthenaClient('5a-datalake')


def read_query(file_name):
    with open(file_name) as f:
        return f.read()


@logger
def delete_old_entries(entity, execution_date=None):
    query = ("delete from staging.{0} where date(slot_dt) = date('{1}')".format(entity, execution_date)
             if execution_date is not None else 'truncate staging.{0}'.format(entity))

    BaseETL.execute_command(
        command=query,
        db_enum=EnumDb.BI_DW,
        commit=True
    )


def load_agents_slots(**kwargs):
    entity = 'agents_slots'

    file_name = '{}/{}.sql'.format(DATALAKE_QUERIES_DIR, entity)
    _logger.info("Reading from S3: {} file:{}".format(datetime.utcnow(), file_name))
    query = read_query(file_name)

    execution_date = kwargs['execution_date'].strftime('%Y-%m-%d')
    data_frame = athena.execute_query_and_return_dataframe(query, False, 0, execution_date)

    delete_old_entries(entity, execution_date)

    _logger.info("START - To Staging: {}".format(datetime.utcnow()))
    BaseETL.dataframe_to_db(
        enum_db=EnumDb.BI_DW,
        df=data_frame,
        table_name='staging.{}'.format(entity),
        encoding='utf-8',
        append=True
    )


def load_agents_scheduling(**kwargs):
    entity = 'agents_scheduling'
    query = read_query('{}/{}.sql'.format(DW_STAGING_QUERIES_DIR, entity))
    execution_date = kwargs['execution_date'].strftime('%Y-%m-%d')

    data_table = BaseETL.from_db_query(
        db_enum=EnumDb.BI_DW,
        query=query.format(execution_date),
        encoding='utf-8'
    )

    delete_old_entries(entity, execution_date)

    BaseETL.to_db(
        db_enum=EnumDb.BI_DW,
        data_table=data_table,
        table_name=entity,
        encoding='utf-8',
        append=True,
        schema='staging'
    )


def load_agents_signed_contracts():
    entity = 'agents_signed_contracts'
    query = read_query('{}/{}.sql'.format(DW_STAGING_QUERIES_DIR, entity))

    data_table = BaseETL.from_db_query(
        db_enum=EnumDb.BI_DW,
        query=query,
        encoding='utf-8'
    )

    BaseETL.to_db(
        db_enum=EnumDb.BI_DW,
        data_table=data_table,
        table_name=entity,
        encoding='utf-8',
        append=False,
        schema='staging'
    )


# create DAG definition
dag = DAG(
    dag_id='bi-agents-availability',
    description='Task to load agents slots availability and scheduling',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 1, 1, 0, 0, 0),
    schedule_interval=env.convert_to_utc_schedule('30 4 * * *'),
    max_active_runs=1
)

# operators
agents_slots = QuintoAndarPythonOperator(
    dag=dag,
    task_id='load_agents_slots',
    python_callable=load_agents_slots,
    provide_context=True
)

agents_scheduling = QuintoAndarPythonOperator(
    dag=dag,
    task_id='load_agents_scheduling',
    python_callable=load_agents_scheduling,
    provide_context=True
)

agents_signed_contracts = QuintoAndarPythonOperator(
    dag=dag,
    task_id='load_agents_signed_contracts',
    python_callable=load_agents_signed_contracts
)

# flow
agents_slots >> agents_scheduling
