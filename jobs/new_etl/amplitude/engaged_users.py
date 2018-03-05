from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger

from __init__ import QUERIES_DIR


class EngagedUsers(object):
    SCHEMA = 'growth_staging'
    TABLE_NAME = 'amplitude_engaged_users'

    @logger
    def __init__(self, s3_bucket):
        self.athena_client = AthenaClient(s3_bucket)

        self.all_dates_query = EngagedUsers.__get_query_from_file_name(
            '{}/engaged_users/prefix_all_dates.sql'.format(QUERIES_DIR))
        self.current_date_query = EngagedUsers.__get_query_from_file_name(
            '{}/engaged_users/prefix_current_date.sql'.format(QUERIES_DIR))
        self.suffix_query = EngagedUsers.__get_query_from_file_name('{}/engaged_users/suffix.sql'.format(QUERIES_DIR))

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
    def get_df(self, prefix, middle, suffix):
        return self.athena_client.execute_query_and_return_dataframe(sql=prefix + middle + suffix)

    @staticmethod
    @logger
    def df_to_dw(df):
        BaseETL.dataframe_to_db(
            df=df,
            table_name='{}.{}'.format(EngagedUsers.SCHEMA, EngagedUsers.TABLE_NAME),
            encoding='utf-8',
            enum_db=EnumDb.BI_DW,
            append=True
        )

    @staticmethod
    @logger
    def truncate_table():
        BaseETL.execute_command(
            command='truncate table {}.{};'.format(EngagedUsers.SCHEMA, EngagedUsers.TABLE_NAME),
            commit=True,
            db_enum=EnumDb.BI_DW
        )

    @logger
    def append_to_table(self, _filter):
        self.__append(_filter=_filter, prefix=self.all_dates_query)
        self.__append(_filter=_filter, prefix=self.current_date_query)

    @logger
    def __append(self, _filter, prefix):
        middle_query = EngagedUsers.__get_query_from_file_name(
            '{}/engaged_users/middle_{}.sql'.format(QUERIES_DIR, _filter))

        df = self.get_df(prefix=prefix,
                         middle=middle_query,
                         suffix=self.suffix_query)

        EngagedUsers.df_to_dw(df=df)
