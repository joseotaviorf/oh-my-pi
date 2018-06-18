from qa_python_utils.default_logger import logger
import os
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag
dir_path = os.path.dirname(os.path.realpath(__file__))
QUERIES_EBDB_DIR = os.path.join(dir_path, '../../../db/1.source/ebdb/queries/supply_demand_funnel')


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
        return self.build_with_tests(
            source_command='call ebdb.list_usuario();',
            table_name='usuario'
        )

    @logger
    def build_user_with_tests(self):
        query = self.get_query(dim_name='user')

        return self.build_with_tests(source_command=query, table_name='usuario')

    @logger
    def get_query(self, dim_name):
        file_name = '{}/{}.sql'.format(QUERIES_EBDB_DIR, dim_name)

        with open(file_name) as f:
            lines = f.read()

        return lines
