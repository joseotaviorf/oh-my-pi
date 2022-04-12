import os
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

logger = QuintoAndarLogger('GrowthAmplitude')


class GrowthAmplitude(object):
    SCHEMA = 'growth_staging'
    DW_SCHEMA = 'growth'

    QUERIES_DIR = '{}/amplitude'.format(DATALAKE_QUERIES_DIR)
    DW_QUERIES_DIR_GROWTH = '{}/growth'.format(DW_QUERIES_DIR)

    @logger
    def __init__(self, measure, s3_bucket):
        data_acc_aws_access_key_id = os.environ.get('DATA_AWS_ACCESS_KEY_ID')
        data_acc_aws_secret_access_key = os.environ.get('DATA_AWS_SECRET_ACCESS_KEY')
        self.athena_client = AthenaClient(s3_bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)
        self.measure = measure
        self.all_dates_query = BaseETL.get_query_from_file_name(
            '{}/{}/prefix_all_dates.sql'.format(GrowthAmplitude.QUERIES_DIR, measure))
        self.current_date_query = BaseETL.get_query_from_file_name(
            '{}/{}/prefix_current_date.sql'.format(GrowthAmplitude.QUERIES_DIR, measure))
        self.suffix_query = BaseETL.get_query_from_file_name('{}/{}/suffix.sql'.format(GrowthAmplitude.QUERIES_DIR,
                                                                                       measure))

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

    @staticmethod
    @logger
    def _drop_table(table_name):
        BaseETL.execute_command(
            command='drop table if exists {}.{};'.format(GrowthAmplitude.DW_SCHEMA, table_name),
            commit=True,
            db_enum=EnumDB.BI_DW
        )

    @staticmethod
    @logger
    def create_table_as_file_query(table_name, level=None, sub_level=None):
        query = BaseETL.get_query_from_file_name(
            '{0}/{1}{2}{3}.sql'.format(GrowthAmplitude.DW_QUERIES_DIR_GROWTH,
                                       ('{}/'.format(level) if level else ''),
                                       ('{}/'.format(sub_level) if sub_level else ''),
                                       table_name))

        GrowthAmplitude._drop_table(table_name)

        query = 'CREATE TABLE {}.{} AS {}'.format(GrowthAmplitude.DW_SCHEMA, table_name, query)

        BaseETL.execute_command(
            command=query,
            commit=True,
            db_enum=EnumDB.BI_DW
        )
