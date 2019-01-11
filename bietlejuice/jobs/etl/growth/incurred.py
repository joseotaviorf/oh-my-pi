from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DW_QUERIES_DIR

logger = QuintoAndarLogger('Growth')


class Growth(object):
    SCHEMA = 'growth'
    QUERIES_DIR = '{}/growth'.format(DW_QUERIES_DIR)
    FACT_TABLE_NAME = 'fact_growth'

    @staticmethod
    @logger
    def get_measure_all_query():
        return BaseETL.get_query_from_file_name('{}/measure_all.sql'.format(Growth.QUERIES_DIR))

    @staticmethod
    @logger
    def get_measure_no_filters_query():
        return BaseETL.get_query_from_file_name('{}/measure_no_filters.sql'.format(Growth.QUERIES_DIR))

    @staticmethod
    @logger
    def get_employee_all_query():
        return BaseETL.get_query_from_file_name('{}/top_funnel/employees/team_all.sql'.format(Growth.QUERIES_DIR))

    @logger
    def load_fact(self):
        Growth.drop_table(table_name=Growth.FACT_TABLE_NAME)
        Growth._execute_file_query('{}/public/{}.sql'.format(DW_QUERIES_DIR, Growth.FACT_TABLE_NAME))

    @staticmethod
    @logger
    def drop_table(table_name, schema='public'):
        BaseETL.execute_command(
            command='drop table if exists {}.{};'.format(schema, table_name),
            commit=True,
            db_enum=EnumDB.BI_DW
        )

    @staticmethod
    @logger
    def create_table(funnel, measure, _filter, period):
        prefix_file = BaseETL.get_query_from_file_name(
            '{}/{}/{}/prefix_{}.sql'.format(Growth.QUERIES_DIR, funnel, measure, _filter))
        suffix_file = BaseETL.get_query_from_file_name('{}/suffix_{}.sql'.format(Growth.QUERIES_DIR, period))

        Growth.execute_command(
            'create table {}.{}_{}_{} as\n{}'.format(Growth.SCHEMA, measure, _filter, period,
                                                     prefix_file + suffix_file))

    @staticmethod
    @logger
    def execute_command(query):
        BaseETL.execute_command(
            command=query,
            commit=True,
            db_enum=EnumDB.BI_DW
        )

    @staticmethod
    @logger
    def _execute_file_query(file_name):
        BaseETL.execute_file_query(
            filename=file_name,
            commit=True,
            db_enum=EnumDB.BI_DW
        )
