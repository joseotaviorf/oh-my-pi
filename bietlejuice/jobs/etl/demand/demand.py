from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

logger = QuintoAndarLogger('Demand_ETL')


class DemandETL(object):
    def __init__(self, s3_bucket, execution_date=None):
        self.s3_bucket = s3_bucket
        self.execution_date = execution_date
        self.athena_client = AthenaClient(self.s3_bucket)

    @logger
    def extract_data(self, table_name):
        filename = self._format_query_filename(filename=table_name)
        return self.athena_client.execute_file_query_and_return_dataframe(filename)

    @logger
    def move_to_datalake(self, df, table_name):
        s3_file_path = 'clean/demand/{0}/{1}.parq'.format(table_name, str(self.execution_date))
        self.athena_client.create_parquet_from_df(key=s3_file_path, df=df)

    @logger
    def _format_query_filename(cls, filename):
        return '{}/demand/{}.sql'.format(DATALAKE_QUERIES_DIR, filename)
