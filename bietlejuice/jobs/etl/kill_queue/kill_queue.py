from gzip import GzipFile
from io import BytesIO

from pandas import DataFrame
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import SOURCE_QUERIES_DIR

logger = QuintoAndarLogger('Asterisk')


class KillQueue(object):

    def __init__(self, s3_bucket=''):
        self.s3_bucket = s3_bucket
        # self.athena_client = AthenaClient(self.s3_bucket)
        # self.s3_resource = boto3.resource('s3')

    # @logger
    def extract_data_and_move_to_raw(self, table):
        query = BaseETL.get_query_from_file_name(
            '{}/kill_queue/extract_{}_data.sql'.format(SOURCE_QUERIES_DIR, table))
        table_data = BaseETL.from_db_query(
            query=query,
            db_enum=EnumDB.QuintoAndar_killqueue
        )
        logger.info('m=extract_data_and_move_to_raw, table={}, msg=data extracted from db'.format(table))
        df = DataFrame(table_data[1:], columns=table_data[0])
        df_json = df.to_json(orient='records', date_format='iso', force_ascii=False)

        gz_body = BytesIO()
        with GzipFile(fileobj=gz_body, mode='w') as fp:
            fp.write(df_json.encode('utf-8'))

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path='raw/kill_queue/{}/data.gz'.format(table)
        )
        logger.info('m=extract_data_and_move_to_raw, table={}, msg=data saved to s3'.format(table))

    def move_data_from_raw_to_clean(self):
        raise NotImplementedError()

    def move_data_from_clean_to_dw(self):
        raise NotImplementedError()


if __name__ == "__main__":
    kq = KillQueue('5a-datalake')
    kq.extract_data_and_move_to_raw('reservation')
