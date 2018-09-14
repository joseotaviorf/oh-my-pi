from datetime import datetime
from datetime import timedelta

from airflow.models import DAG
from qa_python_utils.default_logger import _logger, logger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import EnumDB, BaseETL
from bietlejuice.jobs.dags import DW_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env

env.set_airflow_var_to_local_env('BI_DW')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')


@logger
def load_agents_performance_ranking(dim_name, query_dir, filename=None, **kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))

    # read query and suffix and concatenate
    if filename is None:
        filename = dim_name
    query_file = '{}/{}.sql'.format(query_dir, filename)
    with open(query_file) as f:
        query = f.read()

    BaseETL.execute_command(
        command=query.format(exec_date),
        commit=True,
        db_enum=EnumDB.BI_DW
    )


@logger
def clean_previous_data(dim_name, schema, date_column, **kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    _logger.info('m=clean_daily_data_in_table, Start query to clean {}: {}'.format(dim_name, exec_date))

    query = '''DELETE FROM {0}.{1}
                USING public.dim_date ddate
                WHERE ddate.date = '{3}'
                AND cast({1}.{2} as varchar) = to_char(ddate.week_start::DATE,'YYYYMMDD')'''.format(schema,
                                                                                                    dim_name,
                                                                                                    date_column,
                                                                                                    exec_date)

    BaseETL.execute_command(
        db_enum=EnumDB.BI_DW,
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

clear_old_data = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='clean_previous_data',
    provide_context=True,
    python_callable=clean_previous_data,
    op_kwargs={'dim_name': 'agents_performance_ranking', 'schema': 'growth', 'date_column': 'sk_date'}
)

tickets_whats = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='load_agents_performance_ranking',
    execution_timeout=timedelta(hours=3),
    provide_context=True,
    python_callable=load_agents_performance_ranking,
    op_kwargs={'dim_name': 'agents_performance_ranking', 'query_dir': '{}/growth/'.format(DW_QUERIES_DIR)}
)

clear_old_data >> tickets_whats
