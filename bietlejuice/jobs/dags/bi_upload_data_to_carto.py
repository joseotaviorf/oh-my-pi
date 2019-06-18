from airflow.models import DAG
from datetime import datetime, timedelta

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.new_base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags.util import environment as env

from bietlejuice.jobs.wrappers.carto.carto_api import CartoApi

from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR

import json
import petl

env.set_airflow_var_to_local_env('BI_DW')
athena = AthenaClient('5a-datalake')
logger = QuintoAndarLogger('bi-doorman-data')
carto_path = 'carto'
CARTO_CREDENTIALS = json.loads(env.get_airflow_env_var('CARTO_CREDENTIALS'))
carto_api = CartoApi(CARTO_CREDENTIALS)


def load_data_and_upload_to_carto(sql_filename, carto_table_name, db, final_sql, **kwargs):
    if db == 'athena':
        queries_dir = DATALAKE_QUERIES_DIR
    elif db == 'dw':
        queries_dir = DW_QUERIES_DIR
    file_name = '{}/{}/{}.sql'.format(queries_dir, carto_path, sql_filename)
    logger.info('m=load_data_and_upload_to_carto, file={}, msg=reading data'.format(file_name))
    query = BaseETL.get_query_from_file_name(file_name)

    if db == 'athena':
        df = athena.execute_query_and_return_dataframe(
            sql=query,
            paginate=False,
            page_size=0)
    elif db == 'dw':
        table = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=query
        )
        df = petl.todataframe(table)

    csv_file_path = '/var/tmp/{}.csv'.format(sql_filename)
    df.to_csv(csv_file_path, index=False, encoding='utf-8')
    if len(df) > 0:
        # upload CSV to CARTO
        create_table_statement = BaseETL.generate_create_table_statement(df, carto_table_name)
        carto_api.run_sql(create_table_statement)
        carto_api.run_sql('TRUNCATE TABLE {}'.format(carto_table_name))
        carto_api.upload_csv(csv_file_path, carto_table_name)
        carto_api.run_sql("SELECT cdb_cartodbfytable('dev', '{}')".format(carto_table_name))
        if final_sql is not None:
            carto_api.run_sql(final_sql)
        # # write result to S3
        # df_export = df
        # cols = df_export.columns.values.tolist()
        # df_export[cols] = df_export[cols].astype(str)
        # key = 'clean/external/{}/{}.parq'.format(carto_table_name, carto_table_name)
        # athena.create_parquet_from_df(key=key, df=df_export)


tasks = [
    {'carto_table_name': 'iptu_bldgs_doormen_data',
     'db': 'athena',
     'final_sql': 'UPDATE iptu_bldgs_doormen_data SET the_geom = ST_SetSRID(ST_MakePoint(lng::float, lat::float), 4326) WHERE the_geom IS NULL'},
    {'carto_table_name': 'cnpj_bldgs_doormen_data',
     'db': 'athena',
     'final_sql': 'UPDATE cnpj_bldgs_doormen_data SET the_geom = ST_SetSRID(ST_MakePoint(lng::float, lat::float), 4326) WHERE the_geom IS NULL'},
    {'carto_table_name': 'qa_subregions',
     'db': 'athena',
     'final_sql': 'UPDATE qa_subregions SET the_geom = ST_GeomFromText(geometry, 4326)'},
    {'carto_table_name': 'dim_house_listing',
     'db': 'athena',
     'final_sql': 'UPDATE dim_house_listing SET the_geom = ST_SetSRID(ST_MakePoint(house_lng::float, house_lat::float), 4326) WHERE the_geom IS NULL'},
    {'carto_table_name': 'qa_listings_online_metrics',
     'db': 'athena',
     'final_sql': None},
    {'carto_table_name': 'qa_listings_metrics',
     'db': 'dw',
     'final_sql': None}
]

MAIN_DAG_NAME = 'bi-upload-data-to-carto'

dag = DAG(
    dag_id=MAIN_DAG_NAME,
    description='Upload data to CARTO',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False,
        'retries': 1,
        'retry_delay': timedelta(minutes=30),
    },
    start_date=datetime(2019, 2, 16, 0, 0, 0),
    schedule_interval='30 9 * * *',
    max_active_runs=1,
    catchup=False
)

operators = []

for task in tasks:
    operator = BaseDAG.build_python_operator(
        dag=dag,
        task_id=task['carto_table_name'],
        python_callable=load_data_and_upload_to_carto,
        op_kwargs={'sql_filename': task['carto_table_name'], 'carto_table_name': task['carto_table_name'],
                   'db': task['db'], 'final_sql': task['final_sql']},
        provide_context=True
    )

    operators.append(operator)
