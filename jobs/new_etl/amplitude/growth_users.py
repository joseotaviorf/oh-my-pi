from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from jobs.new_etl.amplitude.__init__ import QUERIES_DIR
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger


class GrowthUsers(object):
    SCHEMA = 'growth_staging'

    @logger
    def __init__(self, measure, s3_bucket):
        self.athena_client = AthenaClient(s3_bucket)
        self.measure = measure

    @logger
    def _get_all_dates_query(self):
        return BaseETL.get_query_from_file_name(
            '{}/{}/prefix_all_dates.sql'.format(QUERIES_DIR, self.measure))

    @logger
    def _get_current_date_query(self):
        BaseETL.get_query_from_file_name(
            '{}/{}/prefix_current_date.sql'.format(QUERIES_DIR, self.measure))

    @logger
    def _get_suffix_query(self, period):
        return BaseETL.get_query_from_file_name('{}/{}/suffix_{}.sql'.format(QUERIES_DIR, self.measure, period))

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
