import petl as etl
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR
from qa_python_utils.default_logger import QuintoAndarLogger

logger = QuintoAndarLogger('Kenshoo')


class Kenshoo(object):
    PREFIX_QUERIES_PATH = 'kenshoo'
    CSV_PATH_PREFIX = '/tmp/kenshoo'

    @logger
    def __init__(self, execution_date):
        self.execution_date = execution_date

    @logger
    def _athena_execute_query_from_file(self, query_filename, athena_client, query_params):
        full_path = '{}/{}/{}'.format(DATALAKE_QUERIES_DIR, Kenshoo.PREFIX_QUERIES_PATH, query_filename)

        return athena_client.execute_file_query_and_return_dataframe(filename=full_path, query_params=query_params)

    @logger
    def _redshift_execute_query_from_file(self, query_filename, query_params=None):
        filename = '{}/{}/{}'.format(DW_QUERIES_DIR, Kenshoo.PREFIX_QUERIES_PATH, query_filename)
        with open(filename) as f:
            query = f.read()

        if query_params:
            query = query.format(**query_params)

        petl_table = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=query,
            encoding='UTF8'
        )

        return etl.todataframe(petl_table)

    @logger(exclude='df')
    def _save_single_file(self, df, file_name=''):
        # saving as csv for later SFTP send
        csv_path = '{}-{}{}.csv'.format(Kenshoo.CSV_PATH_PREFIX, file_name, self.execution_date)
        df.to_csv(
            path_or_buf=csv_path,
            index=False,
            encoding='utf-8'
        )

        logger.info('m=_save_single_file, msg=csv saved to {}'.format(csv_path))

    @logger(exclude='df')
    def _save_multiple_files(self, df, query_filename, split_by_column=None):
        # splitting
        df_index = df[split_by_column].unique()

        for row in df_index:
            # saving as csv for later SFTP send
            csv_path = '{}-{}-{}.csv'.format(Kenshoo.CSV_PATH_PREFIX, query_filename.replace('.sql', ''),
                                             row.encode('ascii', 'ignore'))

            df[df[split_by_column] == row].to_csv(
                path_or_buf=csv_path,
                index=False,
                encoding='utf-8'
            )

            logger.info('m=_save_multiple_files, index={}, msg=csv saved to {}'.format(
                row.encode('ascii', 'ignore'), csv_path))

    @logger(exclude='athena_client')
    def save_file_from_athena_query_execution(self, query_filename, athena_client, file_name, query_params=None):
        if query_filename is None or '.sql' not in query_filename:
            raise RuntimeError('m=save_file_from_athena_query_execution, msg=query_filename is invalid')

        if athena_client is None:
            raise RuntimeError('m=save_file_from_athena_query_execution, msg=athena_client param is mandatory')

        df = self._athena_execute_query_from_file(query_filename=query_filename, athena_client=athena_client,
                                                  query_params=query_params)

        self._save_single_file(df=df, file_name=file_name)

    @logger
    def save_file_from_redshift_query_execution(self, query_filename, query_params=None, split_by_column=None,
                                                file_name=''):
        if query_filename is None or '.sql' not in query_filename:
            raise RuntimeError('m=save_file_from_redshift_query_execution, msg=query_filename is invalid')

        df = self._redshift_execute_query_from_file(query_filename=query_filename, query_params=query_params)

        if split_by_column:
            self._save_multiple_files(df=df, query_filename=query_filename, split_by_column=split_by_column)
        else:
            self._save_single_file(df=df, file_name=file_name)
