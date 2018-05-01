from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.enum_db import EnumDb


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
                ('emptiness_dim_contract', ContractSubDag.__test_emptiness)
            ]
        )

    @staticmethod
    def __test_duplicates():
        if BaseTest.contains_duplicates(
                schema='staging',
                table='dim_contract',
                key='sk_contract',
                enum_db=EnumDb.BI_ODS
        ):
            _logger.error('m=__test_duplicates, msg=dim_contract has duplicates')
            raise Exception

        _logger.info('m=__test_duplicates, msg=dim_contract is free from duplicates')

    @staticmethod
    def __test_emptiness():
        if BaseTest.is_empty(
                schema='staging',
                table='dim_contract',
                enum_db=EnumDb.BI_ODS
        ):
            _logger.error('m=__test_emptiness, msg=dim_contract is empty')
            raise Exception

        _logger.info('m=__test_emptiness, msg=dim_contract is not empty')
