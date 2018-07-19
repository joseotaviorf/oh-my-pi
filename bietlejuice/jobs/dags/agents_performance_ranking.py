import os
from datetime import datetime
from datetime import timedelta

from airflow.models import DAG
from airflow.operators.quintoandar import QuintoAndarPythonOperator
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from bietlejuice.jobs.dags.util import environment as env
from qa_python_utils.default_logger import _logger, logger

dir_path = os.path.dirname(os.path.realpath(__file__))
PROD_QUERIES_DIR = os.path.join(dir_path, '../../db/3.dw/growth/prod/queries')
env.set_airflow_var_to_local_env(
    'BI_DW',
    'AWS_ACCESS_KEY_ID',
    'AWS_SECRET_ACCESS_KEY',
    'AWS_DEFAULT_REGION'
)
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')


@logger
def load_agents_performance_ranking(dim_name, query_dir, filename=None, **kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))

    clean_previous_data(enum=EnumDb.BI_DW, schema='growth', table_name='agents_performance_ranking',
                        date_column='sk_date', dt=exec_date)

    # read query and suffix and concatenate
    if filename is None:
        filename = dim_name
    query_file = '{}/{}.sql'.format(query_dir, filename)
    with open(query_file) as f:
        query = f.read()

    BaseETL.execute_command(
        command=query.format(exec_date),
        commit=True,
        db_enum=EnumDb.BI_DW
    )


@logger
def clean_previous_data(enum, schema, table_name, date_column, dt):
    _logger.info('m=clean_daily_data_in_table, Start query to clean {}: {}'.format(table_name, str(dt)))

    query = "DELETE FROM {}.{} WHERE cast({} as varchar) = to_char('{}'::DATE,'YYYYMMDD')".format(schema, table_name,
                                                                                                  date_column, str(dt))

    BaseETL.execute_command(
        db_enum=enum,
        encoding='UTF8',
        command=query,
        commit=True
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
    schedule_interval=env.convert_to_utc_schedule('0 6 * * 1'),
    max_active_runs=1
)

tickets_whats = QuintoAndarPythonOperator(
    dag=dag,
    task_id='load_agents_performance_ranking',
    execution_timeout=timedelta(hours=3),
    provide_context=True,
    python_callable=load_agents_performance_ranking,
    op_kwargs={'dim_name': 'agents_performance_ranking', 'query_dir': PROD_QUERIES_DIR}
)

if __name__ == '__main__':
    load_agents_performance_ranking('agents_performance_ranking', PROD_QUERIES_DIR, None,
                                    execution_date=datetime.today())
