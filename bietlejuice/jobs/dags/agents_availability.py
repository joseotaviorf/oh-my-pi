from datetime import datetime
import os
from airflow import DAG
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env

env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
athena = AthenaClient(bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)

logger = QuintoAndarLogger('bi-agents-availability')


def read_query(file_name):
    with open(file_name) as f:
        return f.read()


@logger
def delete_old_entries(entity, execution_date=None):
    query = ("delete from agent.{0} where date(slot_dt) >= date('{1}')".format(
        entity, execution_date) if execution_date is not None
        else 'truncate agent.{0}'.format(entity))

    BaseETL.execute_command(
        command=query,
        db_enum=EnumDB.BI_DW,
        commit=True
    )


def load_agents_slots(**kwargs):
    entity = 'agents_slots'

    file_name = '{}/{}.sql'.format(DATALAKE_QUERIES_DIR, entity)
    logger.info(
        "Reading from S3: {} file:{}".format(datetime.utcnow(), file_name))
    query = read_query(file_name)

    execution_date = kwargs['execution_date'].strftime('%Y-%m-%d')
    data_frame = athena.execute_query_and_return_dataframe(
        sql=query,
        paginate=False,
        page_size=0,
        query_params={'dt': execution_date})

    delete_old_entries(entity, execution_date)

    logger.info("START - To DW: {}".format(datetime.utcnow()))
    BaseETL.dataframe_to_db(
        enum_db=EnumDB.BI_DW,
        df=data_frame,
        table_name='agent.{}'.format(entity),
        encoding='utf-8',
        append=True
    )


def load_agents_scheduling(**kwargs):
    entity = 'agents_scheduling'
    query = read_query('{}/agent/{}.sql'.format(DW_QUERIES_DIR, entity))
    execution_date = kwargs['execution_date'].strftime('%Y-%m-%d')

    data_table = BaseETL.from_db_query(
        db_enum=EnumDB.BI_DW,
        query=query.format(execution_date),
        encoding='utf-8'
    )

    delete_old_entries(entity, execution_date)

    BaseETL.to_db(
        db_enum=EnumDB.BI_DW,
        data_table=data_table,
        table_name=entity,
        encoding='utf-8',
        append=True,
        schema='agent'
    )


def load_agents_signed_contracts():
    entity = 'agents_signed_contracts'
    query = read_query('{}/agent/{}.sql'.format(DW_QUERIES_DIR, entity))

    data_table = BaseETL.from_db_query(
        db_enum=EnumDB.BI_DW,
        query=query,
        encoding='utf-8'
    )

    BaseETL.to_db(
        db_enum=EnumDB.BI_DW,
        data_table=data_table,
        table_name=entity,
        encoding='utf-8',
        append=False,
        schema='agent'
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
agents_slots = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_agents_slots',
    python_callable=load_agents_slots,
    provide_context=True
)

agents_scheduling = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_agents_scheduling',
    python_callable=load_agents_scheduling,
    provide_context=True
)

agents_signed_contracts = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_agents_signed_contracts',
    python_callable=load_agents_signed_contracts
)

# flow
agents_slots >> agents_scheduling
