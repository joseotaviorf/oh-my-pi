from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDb
from qa_python_utils.default_logger import _logger, logger
from bietlejuice.jobs.new_etl import SORTINGHAT_QUERIES_DIR


class SortingHat(object):
    ODS_SCHEMA = 'sortinghat'

    @logger
    def extract_table_from_db(self, query_file_path):
        return BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_sortinghat,
            encoding='UTF8',
            query=BaseETL.get_query_from_file_name('{}/{}'.format(SORTINGHAT_QUERIES_DIR, query_file_path))
        )

    @logger(exclude='data_table')
    def load_table_to_s3(self, table_name, data_table, s3_bucket):
        _logger.info('m=table_extraction_and_load, msg={} - to s3'.format(table_name))
        BaseETL.to_s3(
            filename='{}.csv'.format(table_name),
            data_table=data_table,
            bucket_folder_path='{}/raw/sorting_hat/{}'.format(s3_bucket, table_name)
        )

    @logger(exclude='data_table')
    def load_table_to_ods(self, table_name, data_table):
        BaseETL.bulk_insert(
            table=data_table,
            table_name='{}.{}'.format(SortingHat.ODS_SCHEMA, table_name),
            db_enum=EnumDb.BI_ODS,
            encoding='UTF8',
            append=False,
            commit=True
        )
