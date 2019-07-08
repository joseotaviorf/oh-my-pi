from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl import DW_QUERIES_DIR

env.set_airflow_var_to_local_env('BI_DW')
# bucket_datalake = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_ID = 'bi-affiliate-segmentation'
MAIN_START_DATE = datetime(2019, 7, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 7 1 * *')


def create_dw_table_via_sql(file_name, table_name, **kwargs):
    # extraction
    query = BaseETL.get_query_from_file_name(file_name='{0}/public/{1}'.format(DW_QUERIES_DIR, file_name))
    affiliate_data = BaseETL.from_db_query(db_enum=EnumDB.BI_DW, query=query)

    # load
    BaseETL.bulk_insert(table=affiliate_data, table_name=table_name, db_enum=EnumDB.BI_DW, append=False,
                        encoding='utf-8')


main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_ID,
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=False
)

create_affiliate_segmentation_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='create_affiliate_segmentation',
    provide_context=True,
    python_callable=create_dw_table_via_sql,
    op_kwargs={'file_name': 'affiliate_segmentation.sql',
               'table_name': 'fact_affiliate_segmentation'}
)
