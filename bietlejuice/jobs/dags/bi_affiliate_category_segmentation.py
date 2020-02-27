from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl import DW_QUERIES_DIR

env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')

MAIN_DAG_ID = 'bi-affiliate-category-segmentation'
MAIN_START_DATE = datetime(2019, 6, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 9 1 * *')


def bulk_insert_data_into_table(file_name, table_name, **kwargs):
    # extraction
    query = BaseETL.get_query_from_file_name(file_name='{0}/public/{1}'.format(DW_QUERIES_DIR, file_name))
    query = query.format(kwargs['execution_date'])
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

create_affiliate_category_segmentation_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='create_affiliate_category_segmentation',
    provide_context=True,
    python_callable=bulk_insert_data_into_table,
    op_kwargs={'file_name': 'affiliate_monthly_category_segmentation.sql',
               'table_name': 'fact_affiliate_monthly_category_segmentations'}
)
