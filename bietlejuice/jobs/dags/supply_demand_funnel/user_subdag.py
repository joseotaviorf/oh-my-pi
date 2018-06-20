from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags.supply_demand_funnel import QUERIES_EBDB_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag
from qa_python_utils.default_logger import logger


class UserSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(UserSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='Usuario',
            ods_stg_table_name='user'
        )

    @logger
    def build_user_with_tests(self):
        file_path = '{}/{}.sql'.format(QUERIES_EBDB_DIR, 'user')
        query = BaseETL.get_query_from_file_name(file_name=file_path)

        return self.build_with_tests(source_command=query, table_name='usuario')
