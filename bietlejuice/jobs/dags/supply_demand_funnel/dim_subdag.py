from qa_python_utils.default_logger import logger

from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import SOURCE_QUERIES_TESTS_DIR


class DimSubDag(BaseSubDag):
    S3_BUCKET = '5a-datalake'

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date, ebdb_table_name,
                 ods_stg_table_name):
        super(DimSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date, ebdb_table_name)
        self.ebdb_table_name = ebdb_table_name
        self.ods_stg_table_name = ods_stg_table_name

    @logger
    def build_with_tests(self, source_command, from_file_query=False, table_name=None):
        return self._build_with_tests(
            entity=self.ods_stg_table_name,
            source_command=source_command,
            tests=[
                ('duplicates_dim_{}'.format(self.ods_stg_table_name), self.__test_duplicates),
                ('emptiness_dim_{}'.format(self.ods_stg_table_name), self.__test_emptiness),
                ('counts_dim_{}'.format(self.ods_stg_table_name),
                 self.__test_counts_from_raw_query if from_file_query is False else self.__test_counts_from_file_query)
            ],
            table_name=table_name
        )

    @logger
    def build_tests_tasks(self, dag, from_file_query=False):
        return self._build_tests_tasks(
            dag=dag,
            tests=[
                ('duplicates_dim_{}'.format(self.ods_stg_table_name), self.__test_duplicates),
                ('emptiness_dim_{}'.format(self.ods_stg_table_name), self.__test_emptiness),
                ('counts_dim_{}'.format(self.ods_stg_table_name),
                 self.__test_counts_from_raw_query if from_file_query is False else self.__test_counts_from_file_query)
            ]
        )

    def __test_duplicates(self):
        BaseTest.check_for_duplicates(
            schema='staging',
            table='dim_{}'.format(self.ods_stg_table_name),
            key='sk_{}'.format(self.ods_stg_table_name),
            enum_db=EnumDB.BI_ODS
        )

    def __test_emptiness(self):
        BaseTest.check_for_emptiness(
            schema='staging',
            table='dim_{}'.format(self.ods_stg_table_name),
            enum_db=EnumDB.BI_ODS
        )

    def __test_counts_from_file_query(self):
        BaseTest.are_counts_equal({
            'acceptable_diff': .5,
            'sources': [
                {
                    'schema': 'staging',
                    'table_name': 'dim_{}'.format(self.ods_stg_table_name),
                    'enum_db': EnumDB.BI_ODS
                },
                {
                    'file_path': '{}/ebdb/{}_count_check.sql'.format(SOURCE_QUERIES_TESTS_DIR, self.ebdb_table_name),
                    'enum_db': EnumDB.QuintoAndar_ebdb,
                    'encoding': 'LATIN1'
                }
            ]
        })

    def __test_counts_from_raw_query(self):
        BaseTest.are_counts_equal({
            'acceptable_diff': .5,
            'sources': [
                {
                    'schema': 'staging',
                    'table_name': 'dim_{}'.format(self.ods_stg_table_name),
                    'enum_db': EnumDB.BI_ODS
                },
                {
                    'schema': 'ebdb',
                    'table_name': self.ebdb_table_name,
                    'enum_db': EnumDB.QuintoAndar_ebdb,
                    'encoding': 'LATIN1'
                }
            ]
        })
