import abc
from datetime import datetime

import s3fs
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger


class StitchTransferRawTemplate(object):
    __metaclass__ = abc.ABCMeta

    @logger
    def __init__(self, bucket, execution_date, integration, database, table, date_field, source_key):
        self.athena = AthenaClient(bucket)
        self.bucket = bucket
        self.execution_date = execution_date
        self.integration = integration
        self.database = database
        self.table = table
        self.date_field = date_field
        self.source_key = source_key

    @abc.abstractmethod
    def build_query(self):
        raise NotImplementedError('m=build_query, msg=method not implemented')

    @abc.abstractmethod
    def copy_files(self, df):
        raise NotImplementedError('m=build_query, msg=method not implemented')

    @abc.abstractmethod
    def build_key(self, _date, account):
        raise NotImplementedError('m=build_query, msg=method not implemented')

    @logger
    def fetch_data(self, query):
        _logger.info("m=_fetch_data, msg=building partition from execution_date")
        partition = datetime.strftime(self.execution_date, "%Y-%m-%d")

        self.athena.add_partition(self.database, self.table, "dt='{}'".format(partition))

        _logger.info("m=_fetch_data, msg=getting dataframe from query")
        return self.athena.execute_query_and_return_dataframe(query)

    @logger(exclude='df')
    def _move_files_to_raw(self, df, key):
        fs = s3fs.S3FileSystem()
        with fs.open("{}/{}".format(self.bucket, key), 'wb') as f:
            _logger.info(
                "m=_move_files_to_raw, msg=moving json files from dataframe to raw bucket, key=s3://{}/{}".format(
                    self.bucket, key))
            f.write(df.to_json(orient='records', lines=True).encode())
