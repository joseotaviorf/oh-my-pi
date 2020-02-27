import os
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

logger = QuintoAndarLogger('Demand_ETL')


class DemandETL(object):
    def __init__(self, s3_bucket):
        self.s3_bucket = s3_bucket

    @logger
    def _extract_data(self, table_name, period):
        dt_param = DemandETL.get_dt_param(period=period)
        data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
        data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
        athena_client = AthenaClient(self.s3_bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)

        if dt_param is None:
            raise ValueError('m=_extract_data, dt_param=None, msg=no period found')

        filename = self.format_query_filename(filename=table_name)
        return athena_client.execute_file_query_and_return_dataframe(filename=filename,
                                                                     query_params={'dt_column': dt_param})

    @logger(exclude=['df', 'raw_columns', 'clean_columns'])
    def _move_to_datalake(self, df, table_name, period, raw_columns, clean_columns):
        data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
        data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
        athena_client = AthenaClient(self.s3_bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)

        s3_file_path = 'clean/demand/{0}/{0}.parq'.format('{}_{}'.format(period, table_name))
        athena_client.create_parquet_from_df(key=s3_file_path, df=df, raw_columns=raw_columns,
                                             clean_columns=clean_columns)

    @staticmethod
    @logger
    def format_query_filename(filename):
        return '{}/demand/{}.sql'.format(DATALAKE_QUERIES_DIR, filename)

    @staticmethod
    @logger
    def get_dt_param(period):
        return {
            'daily': 'date',
            'weekly': 'week_start',
            'monthly': 'month_start'
        }.get(period)
