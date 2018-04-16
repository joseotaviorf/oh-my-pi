from datetime import datetime, timedelta
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from bietlejuice.jobs.dags.util import environment as env
from airflow.models import DAG
from qa_python_utils.default_logger import _logger
from qa_python_utils.aws.athena import AthenaClient
from airflow.operators.quintoandar import QuintoAndarPythonOperator
from bietlejuice.jobs.new_etl.dim_utils import load_dim_from_ods_to_dw
import os

dir_path = os.path.dirname(os.path.realpath(__file__))
QUERIES_DIR = os.path.join(dir_path, '../../db/2.datalake/queries')
env.set_airflow_var_to_local_env(
    'BI_DW',
    'AWS_ACCESS_KEY_ID',
    'AWS_SECRET_ACCESS_KEY',
    'AWS_DEFAULT_REGION'
)
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
athena = AthenaClient('5a-datalake')


def load_agents_slots(query_dir, filename=None):
    file_name = '{}/{}.sql'.format(query_dir, filename)
    _logger.info("Reading from S3: {} file:{}".format(datetime.utcnow(), file_name))
    data_frame = athena.execute_file_query_and_return_dataframe(file_name)

    _logger.info("START - To Staging: {}".format(datetime.utcnow()))
    BaseETL.dataframe_to_db(
        enum_db=EnumDb.BI_DW,
        df=data_frame,
        table_name='staging.agents_slots',
        encoding='utf-8',
        append=False
    )

# create DAG definition
dag = DAG(
    dag_id='bi-agents-slots',
    description='Task to load agents slots availability',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 3, 12, 0, 0, 0),
    schedule_interval=env.convert_to_utc_schedule('30 4 * * *'),
    max_active_runs=1
)

tickets_whats = QuintoAndarPythonOperator(
    dag=dag,
    task_id='load_agents_slots',
    python_callable=load_agents_slots,
    op_kwargs={'query_dir': QUERIES_DIR, 'filename': 'agents_slots'}
)