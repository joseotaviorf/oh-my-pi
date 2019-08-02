from datetime import datetime

from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env

# env vars
env.set_airflow_var_to_local_env('PHOTOS_MATCHER')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_ID = 'bi-photos-matcher'
MAIN_START_DATE = datetime(2019, 7, 29)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 9 * * *')

logger = QuintoAndarLogger(MAIN_DAG_ID)


# functions
@logger
def extract_data_from_matcher(table_name, **kwargs):
    # connect to external db, extract data, save csv to S3
    query = "SELECT id, crawled_listing_id, sk_house_listing, match, created_on FROM crawler_matches WHERE created_on::DATE = CURRENT_DATE;"

    logger.info('m=extract_data_from_matcher, table_name={}, msg=Extracting data from photos matcher'.format(table_name))
    data_table = BaseETL.from_db_query(
        db_enum=EnumDB.QuintoAndar_photos_matcher,
        query=query,
        encoding='utf-8'
    )
    BaseETL.to_s3(
        filename='{}_{}.csv'.format(kwargs['current_date_string'], table_name),
        data_table=data_table,
        bucket_folder_path='{}/raw/photos_matcher/{}'.format(s3_bucket, table_name),
        write_header=False
    )


def upload_data_to_matcher(table_name, **kwargs):
    # extract data from athena, save to external db
    athena = AthenaClient(s3_bucket)
    query = BaseETL.get_query_from_file_name('./bietlejuice/db/datalake/queries/photos_matcher/{}.sql'.format(table_name))

    logger.info('m=upload_data_to_matcher, table_name={}, msg=Reading data from datalake'.format(table_name))
    execution_date = kwargs['execution_date'].strftime('%Y-%m-%d')
    df = athena.execute_query_and_return_dataframe(
        sql=query,
        query_params={'dt': execution_date}
    )

    logger.info('m=upload_data_to_matcher, table_name={}, msg=Truncating table in photos matcher db'.format(table_name))
    BaseETL.execute_command(
        command='TRUNCATE TABLE public.{}'.format(table_name),
        db_enum=EnumDB.QuintoAndar_photos_matcher,
        encoding='utf-8',
        commit=True
    )

    logger.info('m=upload_data_to_matcher, table_name={}, msg=Writing data to photos matcher db'.format(table_name))
    BaseETL.dataframe_to_db(
        enum_db=EnumDB.QuintoAndar_photos_matcher,
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
    op_kwargs={'table_name': 'crawler_matches', 'current_date_string': datetime.now().strftime('%Y%m%d')}
)

upload_data_to_matcher_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='upload_data_to_matcher_task',
    provide_context=True,
    python_callable=upload_data_to_matcher,
    op_kwargs={'table_name': 'crawler_listings'}
)

extract_data_from_matcher_task >> upload_data_to_matcher_task
