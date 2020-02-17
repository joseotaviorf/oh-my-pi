from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR

logger = QuintoAndarLogger('KillQueue')


class KillQueue(object):

    def __init__(self, s3_bucket):
        self.s3_bucket = s3_bucket
        self.athena_client = AthenaClient(self.s3_bucket)

    def _move_data_from_raw_to_clean(self, table, r_cols, c_cols):
        query = BaseETL.get_query_from_file_name(
            '{}/kill_queue/{}.sql'.format(DATALAKE_QUERIES_DIR, table))
        self.athena_client.create_parquet_from_query(
            key='clean/kill_queue/{}/data.parq'.format(table),
            query=query,
            raw_columns=r_cols, clean_columns=c_cols)
