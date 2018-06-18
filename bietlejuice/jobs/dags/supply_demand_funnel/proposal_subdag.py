import os

from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag
from qa_python_utils.default_logger import logger

dir_path = os.path.dirname(os.path.realpath(__file__))
QUERIES_EBDB_DIR = os.path.join(dir_path, '../../../db/1.source/ebdb/queries/supply_demand_funnel')


class ProposalSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(ProposalSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='Proposta',
            ods_stg_table_name='proposal'
        )

    @logger
    def build_proposal_with_tests(self):
        query = self.get_query(dim_name='proposal')

        return self.build_with_tests(source_command=query)

    @logger
    def get_query(self, dim_name):
        file_name = '{}/{}.sql'.format(QUERIES_EBDB_DIR, dim_name)

        with open(file_name) as f:
            lines = f.read()

        return lines
