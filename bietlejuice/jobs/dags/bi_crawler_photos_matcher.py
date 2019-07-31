from datetime import datetime

from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env

# env vars
# FIXME: var for db string
env.set_airflow_var_to_local_env('BI_DW')
matcher_db_uri = env.get_airflow_env_var('crawler-photos-matcher-db-uri')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_ID = 'bi-crawler-photos-matcher'
MAIN_START_DATE = datetime(2019, 7, 29)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 9 * * *')

logger = QuintoAndarLogger(MAIN_DAG_ID)


# functions
@logger
def extract_data_from_matcher(table_name, **kwargs):
    # connect to external db, extract data, save csv dump to S3
    query = 'SELECT id, crawler_id, sk_house_listing, match, created_on FROM crawler_matches;'

    # logger.info('m=create_datamart_from_dw, table_name={}, msg=Creating table'.format(table_name))
    # BaseETL.execute_command(
    #     command='create table {}.{} as ({})'.format(DATAMARTS_SCHEMA, table_name, query.replace(';', '')),
    #     db_enum=EnumDB.BI_DW,
    #     encoding='utf-8',
    #     commit=True
    # )


def upload_data_to_matcher(table_name, **kwargs):
    # extract data from athena, save to external db
    athena = AthenaClient(s3_bucket)
    query = BaseETL.get_query_from_file_name('./bietlejuice/db/datalake/queries/crawler_photos_matcher/{}.sql'.format(table_name))

    logger.info('m=upload_data_to_matcher, table_name={}, msg=Reading data'.format(table_name))
    execution_date = kwargs['execution_date'].strftime('%Y-%m-%d')
    df = athena.execute_query_and_return_dataframe(
        sql=query,
        query_params={'dt': execution_date}
    )

    logger.info('m=upload_data_to_matcher, table_name={}, msg=Dropping table'.format(table_name))
    BaseETL.execute_command(
        command='DROP TABLE IF EXISTS public.{}'.format(table_name),
        db_enum=EnumDB.BI_DW,
        encoding='utf-8',
        commit=True
    )

    logger.info('m=upload_data_to_matcher, table_name={}, msg=Writing data to matcher db'.format(table_name))
    BaseETL.dataframe_to_db(
        enum_db=EnumDB.BI_DW,
        df=df,
        table_name='public.{}'.format(table_name),
        encoding='utf-8',
        append=False
    )


# dags
main_dag = DAG(
    dag_id=MAIN_DAG_ID,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False
)

extract_data_from_matcher_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='extract_data_from_matcher',
    provide_context=True,
    python_callable=extract_data_from_matcher,
    op_kwargs={'table_name': 'crawler_matches'}
)

upload_data_to_matcher_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='upload_data_to_matcher_task',
    provide_context=True,
    python_callable=upload_data_to_matcher,
    op_kwargs={'table_name': 'crawler_listings'}
)

extract_data_from_matcher_task >> upload_data_to_matcher_task
