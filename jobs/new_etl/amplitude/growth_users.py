from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger

from __init__ import QUERIES_DIR


class GrowthUsers(object):
    SCHEMA = 'growth_staging'

    @logger
    def __init__(self, measure, s3_bucket):
        self.athena_client = AthenaClient(s3_bucket)

        self.all_dates_query = GrowthUsers._get_query_from_file_name(
            '{}/{}/prefix_all_dates.sql'.format(QUERIES_DIR, measure))
        self.current_date_query = GrowthUsers._get_query_from_file_name(
            '{}/{}/prefix_current_date.sql'.format(QUERIES_DIR, measure))
        self.suffix_query = GrowthUsers._get_query_from_file_name('{}/{}/suffix'.format(QUERIES_DIR, measure))

    @staticmethod
    @logger
    def _get_query_from_file_name(file_name):
        try:
            with open(file_name) as f:
                return f.read()
        except IOError:
            _logger.info('m=get_query_from_file_name, file_name={}, msg=file not found'.format(file_name))
            return ''

    @logger
    def get_df(self, prefix, middle, suffix):
        return self.get_df(prefix, suffix, middle)

    @logger
    def get_df(self, prefix, suffix):
        return self.get_df(prefix, suffix)

    @logger
    def get_df(self, prefix, suffix, middle=''):
        return self.athena_client.execute_query_and_return_dataframe(sql=prefix + middle + suffix)

    @staticmethod
    @logger(exclude='df')
    def df_to_dw(df, table_name):
        BaseETL.dataframe_to_db(
            df=df,
            table_name='{}.{}'.format(GrowthUsers.SCHEMA, table_name),
            encoding='utf-8',
            enum_db=EnumDb.BI_DW,
            append=True
        )

    @staticmethod
    @logger
    def truncate_table(table_name):
        BaseETL.execute_command(
            command='truncate table {}.{};'.format(GrowthUsers.SCHEMA, table_name),
            commit=True,
            db_enum=EnumDb.BI_DW
        )
