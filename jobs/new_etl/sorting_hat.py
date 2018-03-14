from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from qa_python_utils.default_logger import _logger, logger


class SortingHat(object):
    @logger
    def extract_table_from_db(self, columns, table_name):
        _logger.info('m=table_extraction_and_load, msg={} - from db'.format(table_name))
        return BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_sortinghat,
            encoding='UTF8',
            query='select {} from "{}";'.format(columns, table_name)
        )

    @logger(exclude='data_table')
    def load_table_to_s3(self, table_name, data_table, s3_bucket):
        _logger.info('m=table_extraction_and_load, msg={} - to s3'.format(table_name))
        BaseETL.to_s3(
            filename='{}.csv'.format(table_name),
            data_table=data_table,
            bucket_folder_path='{}/raw/sorting_hat/{}'.format(s3_bucket, table_name)
        )
