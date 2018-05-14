from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDb
from qa_python_utils.default_logger import logger


class GodFather(object):
    SCHEMA = 'business'

    @staticmethod
    @logger
    def __get_table(table_name):
        return BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_godfather,
            query='select * from {}.{};'.format(GodFather.SCHEMA, table_name),
            encoding='utf-8'
        )

    @staticmethod
    @logger
    def to_s3(s3_bucket, table_name):
        table_data = GodFather.__get_table(table_name)
        BaseETL.to_s3(
            filename='{}_{}.csv'.format(GodFather.SCHEMA, table_name),
            data_table=table_data,
            bucket_folder_path='{}/raw/godfather/{}/{}'.format(s3_bucket, GodFather.SCHEMA, table_name),
            write_header=False
        )
