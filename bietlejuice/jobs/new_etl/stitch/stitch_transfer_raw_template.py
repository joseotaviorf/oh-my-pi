import abc
from datetime import datetime

import s3fs
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger


class StitchTransferRawTemplate(object):
    __metaclass__ = abc.ABCMeta

    @logger
    def __init__(self, bucket, execution_date, integration, database, table, date_field):
        self.athena = AthenaClient(bucket)
        self.bucket = bucket
        self.execution_date = execution_date
        self.integration = integration
        self.database = database
        self.table = table
        self.date_field = date_field
        self.source_key = "raw/market_cost/{integration}/{table}/acc={account}/dt={date_partition}/{file_name}.jsonl"

    def execute(self):
        query = self.build_query()
        df = self._fetch_data(query)
        self.copy_files(df)

    @abc.abstractmethod
    def build_query(self):
        pass

    @abc.abstractmethod
    def copy_files(self, df):
        pass

    @abc.abstractmethod
    def build_key(self, _date, account):
        pass

    @logger
    def _fetch_data(self, query):
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
