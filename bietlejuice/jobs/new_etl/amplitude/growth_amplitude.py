from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger

from __init__ import QUERIES_DIR
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB


class GrowthAmplitude(object):
    SCHEMA = 'growth_staging'

    @logger
    def __init__(self, measure, s3_bucket):
        self.athena_client = AthenaClient(s3_bucket)
        self.measure = measure
        self.all_dates_query = BaseETL.get_query_from_file_name(
            '{}/{}/prefix_all_dates.sql'.format(QUERIES_DIR, measure))
        self.current_date_query = BaseETL.get_query_from_file_name(
            '{}/{}/prefix_current_date.sql'.format(QUERIES_DIR, measure))
        self.suffix_query = BaseETL.get_query_from_file_name('{}/{}/suffix.sql'.format(QUERIES_DIR, measure))

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
    def _df_to_dw(df, table_name):
        BaseETL.dataframe_to_db(
            df=df,
            table_name='{}.{}'.format(GrowthAmplitude.SCHEMA, table_name),
            encoding='utf-8',
            enum_db=EnumDB.BI_DW,
            append=True
        )

    @staticmethod
    @logger
    def _truncate_table(table_name):
        BaseETL.execute_command(
            command='truncate table {}.{};'.format(GrowthAmplitude.SCHEMA, table_name),
            commit=True,
            db_enum=EnumDB.BI_DW
        )
