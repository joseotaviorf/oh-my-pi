from qa_python_utils.default_logger import logger

from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.enum_db import EnumDb
from bietlejuice.jobs.dags import EBDB_TEST_QUERIES_DIR, ODS_STAGING_TEST_QUERIES_DIR


class ContractSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(ContractSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)

    @logger
    def build_with_tests(self):
        return self._build_with_tests(
            entity='contract',
            source_command='call ebdb.list_contrato();',
            tests=[
                ('duplicates_dim_contract', ContractSubDag.__test_duplicates),
                ('emptiness_dim_contract', ContractSubDag.__test_emptiness),
                ('counts_dim_contract', ContractSubDag.__test_counts())
            ]
        )

    @staticmethod
    def __test_duplicates():
        BaseTest.check_for_duplicates(
            schema='staging',
            table='dim_contract',
            key='sk_contract',
            enum_db=EnumDb.BI_ODS
        )

    @staticmethod
    def __test_emptiness():
        BaseTest.check_for_emptiness(
            schema='staging',
            table='dim_contract',
            enum_db=EnumDb.BI_ODS
        )


    @staticmethod
    def __test_counts():
        BaseTest.are_counts_equal({
            'acceptable_diff': .0,
            'sources': [
                {
                    'file_path': '{}/dim_contract_count_check.sql'.format(ODS_STAGING_TEST_QUERIES_DIR),
                    'enum_db': EnumDb.BI_ODS
                },
                {
                    'file_path': '{}/contrato_count_check.sql'.format(EBDB_TEST_QUERIES_DIR),
                    'enum_db': EnumDb.QuintoAndar_ebdb,
                    'encoding': 'LATIN1'
                }
            ]
        })
