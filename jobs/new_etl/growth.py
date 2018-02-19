from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from qa_python_utils.default_logger import logger, _logger

from __init__ import DW_DIR


class Growth(object):
    SCHEMA = 'growth'
    QUERIES_DIR = '{}/{}'.format(DW_DIR, 'growth/prod/queries')

    @staticmethod
    @logger
    def get_measure_all_query():
        return Growth.__get_query_from_file_name('{}/measure_all.sql'.format(Growth.QUERIES_DIR))

    @staticmethod
    @logger
    def get_measure_no_filters_query():
        return Growth.__get_query_from_file_name('{}/measure_no_filters.sql'.format(Growth.QUERIES_DIR))

    @staticmethod
    @logger
    def get_employee_all_query():
        return Growth.__get_query_from_file_name('{}/top_funnel/employees/team_all.sql'.format(Growth.QUERIES_DIR))

    @staticmethod
    @logger
    def __get_query_from_file_name(file_name):
        try:
            with open(file_name) as f:
                return f.read()
        except IOError:
            _logger.info('m=get_query_from_file_name, file_name={}, msg=file not found'.format(file_name))
            return ''

    @logger
    def load_fact(self, query_path):
        self.drop_table('fact_table')

        BaseETL.execute_file_query(
            filename='{}/{}.sql'.format(Growth.QUERIES_DIR, query_path),
            commit=True,
            db_enum=EnumDb.BI_DW
        )

    @logger
    def drop_table(self, table_name):
        BaseETL.execute_command(
            command='drop table if exists {}.{};'.format(Growth.SCHEMA, table_name),
            commit=True,
            db_enum=EnumDb.BI_DW
        )

    @logger
    def create_table(self, funnel, measure, _filter, period):
        prefix_file = Growth.__get_query_from_file_name(
            '{}/{}/{}/prefix_{}.sql'.format(Growth.QUERIES_DIR, funnel, measure, _filter))
        suffix_file = Growth.__get_query_from_file_name('{}/suffix_{}.sql'.format(Growth.QUERIES_DIR, period))

        self.execute_command(
            'create table {}.{}_{}_{} as\n{}'.format(Growth.SCHEMA, measure, _filter, period,
                                                     prefix_file + suffix_file))

    @logger
    def execute_command(self, query):
        BaseETL.execute_command(
            command=query,
            commit=True,
            db_enum=EnumDb.BI_DW
        )
