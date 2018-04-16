from datetime import datetime, timedelta
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from bietlejuice.jobs.dags.util import environment as env
from airflow.models import DAG
from airflow.operators.quintoandar import QuintoAndarPythonOperator
from bietlejuice.jobs.new_etl.dim_utils import load_dim_from_ods_to_dw
import os

dir_path = os.path.dirname(os.path.realpath(__file__))
PROD_QUERIES_DIR = os.path.join(dir_path, '../../db/3.dw/growth/prod/queries')
env.set_airflow_var_to_local_env(
    'BI_DW',
    'AWS_ACCESS_KEY_ID',
    'AWS_SECRET_ACCESS_KEY',
    'AWS_DEFAULT_REGION'
)
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')


def load_agents_performance_ranking(dim_name, query_dir, filename=None):
    # read query and suffix and concatenate
    if filename is None:
        filename = dim_name
    query_file = '{}/{}.sql'.format(query_dir, filename)
    with open(query_file) as f:
        query = f.read()

    BaseETL.execute_command(
        command=query,
        commit=True,
        db_enum=EnumDb.BI_DW
    )

# create DAG definition
dag = DAG(
    dag_id='bi-agents-ranking',
    description='Task to generate new agents ranking every monday',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 19, 0, 0, 0),
    schedule_interval=env.convert_to_utc_schedule('0 3 * * 1'),
    max_active_runs=1
)

tickets_whats = QuintoAndarPythonOperator(
    dag=dag,
    task_id='load_agents_performance_ranking',
    execution_timeout=timedelta(hours=3),
    python_callable=load_agents_performance_ranking,
    op_kwargs={'dim_name': 'agents_performance_ranking', 'query_dir': PROD_QUERIES_DIR}
)