from airflow.models import DAG
from datetime import datetime, timedelta

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env

from bietlejuice.jobs.wrappers.carto.carto_api import CARTO_API

from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR

env.set_airflow_var_to_local_env('BI_DW')
athena = AthenaClient('5a-datalake')
logger = QuintoAndarLogger('bi-doorman-data')


def read_query(file_name):
    with open(file_name) as f:
        return f.read()


def load_building_doorman_data(**kwargs):
    sql_filename = 'building_join_doorman'

    file_name = '{}/{}.sql'.format(DATALAKE_QUERIES_DIR, sql_filename)
    logger.info("Reading from S3: {} file:{}".format(datetime.utcnow(), file_name))
    query = read_query(file_name)

    execution_date = kwargs['execution_date'].strftime('%Y-%m-%d')
    df = athena.execute_query_and_return_dataframe(
        sql=query,
        paginate=False,
        page_size=0,
        query_params={'dt': execution_date})

    # FIXME: tmp folder
    csv_file_path = 'tmp/doorman_data.csv'
    df.to_csv(csv_file_path, index=False, encoding='utf-8')
    # FIXME: log carto actions below
    if len(df) > 0:
        # upload CSV to CARTO
        carto_table_name = 'iptu_bldgs_doormen_data'
        print(CARTO_API.run_sql('TRUNCATE TABLE {}'.format(carto_table_name)))
        print(CARTO_API.upload_csv(csv_file_path, carto_table_name))
        print(CARTO_API.run_sql('UPDATE {} SET the_geom = ST_SetSRID(ST_MakePoint(lng, lat), 4326) WHERE the_geom IS NULL'.format(carto_table_name)))
        # write result to S3
        df_export = df
        cols = df_export.columns.values.tolist()
        # FIXME: use types since in clean?
        df_export[cols] = df_export[cols].astype(str)
        key = 'clean/external/{}/{}.parq'.format(carto_table_name, carto_table_name)
        athena.create_parquet_from_df(key=key, df=df_export)


def load_region_polygons(**kwargs):
    sql_filename = 'extract_region_polygons'

    file_name = '{}/{}.sql'.format(DATALAKE_QUERIES_DIR, sql_filename)
    logger.info("Reading from S3: {} file:{}".format(datetime.utcnow(), file_name))
    query = read_query(file_name)

    execution_date = kwargs['execution_date'].strftime('%Y-%m-%d')
    df = athena.execute_query_and_return_dataframe(
        sql=query,
        paginate=False,
        page_size=0,
        query_params={'dt': execution_date})

    # FIXME: tmp folder
    csv_file_path = 'tmp/region_polygons.csv'
    df.to_csv(csv_file_path, index=False, encoding='utf-8')
    # FIXME: log carto actions below
    if len(df) > 0:
        # upload CSV to CARTO
        carto_table_name = 'qa_subregions'
        print(CARTO_API.run_sql('TRUNCATE TABLE {}'.format(carto_table_name)))
        print(CARTO_API.upload_csv(csv_file_path, carto_table_name))
        print(CARTO_API.run_sql('UPDATE {} SET the_geom = ST_GeomFromText(geometry, 4326)'.format(carto_table_name)))


dag = DAG(
    dag_id='join-buildings-to-doorman',
    description='Join buildings to doorman and upload to CARTO',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False,
        'retries': 1,
        'retry_delay': timedelta(minutes=30),
    },
    start_date=datetime(2019, 2, 16, 0, 0, 0),
    schedule_interval='30 9 * * *',
    max_active_runs=1
)

# operators
building_doorman_data = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_building_doorman_data',
    python_callable=load_building_doorman_data,
    provide_context=True
)

regions_data = BaseDAG.build_python_operator(
    dag=dag,
    task_id='load_region_polygons',
    python_callable=load_region_polygons,
    provide_context=True
)

# flow
building_doorman_data >> regions_data
