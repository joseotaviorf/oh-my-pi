from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR

logger = QuintoAndarLogger('Kenshoo')


class Kenshoo(object):
    PREFIX_QUERIES_PATH = 'kenshoo'
    CSV_PATH_PREFIX = '/tmp/kenshoo'

    @logger
    def __init__(self, athena_client, execution_date):
        self.athena_client = athena_client
        self.execution_date = execution_date

    @logger
    def execute_query_from_file(self, query_filename):
        if query_filename is None or '.sql' not in query_filename:
            raise RuntimeError('m=execute_query_from_file, msg=query_filename is invalid')

        full_path = '{}/{}/{}'.format(DATALAKE_QUERIES_DIR, Kenshoo.PREFIX_QUERIES_PATH, query_filename)
        df = self.athena_client.execute_file_query_and_return_dataframe(filename=full_path)

        # saving as csv for later SFTP send
        csv_path = '{}-{}.csv'.format(Kenshoo.CSV_PATH_PREFIX, self.execution_date)
        df.to_csv(
            path_or_buf=csv_path,
            index=False,
            encoding='utf-8'
        )

        logger.info('m=execute_query_from_file, query_filename={}, msg=csv saved to {}'.format(query_filename,
                                                                                               csv_path))
