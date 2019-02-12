from gzip import GzipFile
from io import BytesIO

from pandas import DataFrame
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR, SOURCE_QUERIES_DIR

logger = QuintoAndarLogger('KillQueue')


class KillQueue(object):

    def __init__(self, s3_bucket):
        self.s3_bucket = s3_bucket
        self.athena_client = AthenaClient(self.s3_bucket)

    @logger
    def _extract_data_and_move_to_raw(self, table):
        query = BaseETL.get_query_from_file_name(
            '{}/kill_queue/extract_{}_data.sql'.format(SOURCE_QUERIES_DIR, table))

        table_data = BaseETL.from_db_query(
            query=query,
            db_enum=EnumDB.QuintoAndar_killqueue,
            encoding='utf8mb4'
        )
        logger.info('m=extract_data_and_move_to_raw, table={}, msg=data extracted from db'.format(table))
        df = DataFrame(table_data[1:], columns=table_data[0])

        gz_body = BytesIO()
        with GzipFile(fileobj=gz_body, mode='w') as fp:
            for _, row in df.iterrows():
                row.to_json(fp, date_format='iso', date_unit='ms', force_ascii=False)
                fp.write('\n')

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path='raw/kill_queue/{}/data.gz'.format(table)
        )
        logger.info('m=extract_data_and_move_to_raw, table={}, msg=data saved to s3'.format(table))

    def _move_data_from_raw_to_clean(self, table, r_cols, c_cols):
        query = BaseETL.get_query_from_file_name(
            '{}/kill_queue/{}.sql'.format(DATALAKE_QUERIES_DIR, table))
        self.athena_client.create_parquet_from_query(
            key='clean/kill_queue/{}/data.parq'.format(table),
            query=query,
            raw_columns=r_cols, clean_columns=c_cols)
