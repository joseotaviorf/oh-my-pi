import time
import unicodedata
from datetime import datetime

import re
from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.new_etl.stitch.stitch_transfer_template import StitchTransferRawTemplate


class AdWordsTransfer(StitchTransferRawTemplate):
    def __init__(self, bucket, execution_date, integration, database, table, date_field, source_key):
        super(AdWordsTransfer, self).__init__(bucket, execution_date, integration, database, table, date_field,
                                              source_key)
        self.adwords_table = table
        self.table = "{}_{}".format(self.integration, self.table)
        self.base_query = """
            SELECT *, DATE(FROM_ISO8601_TIMESTAMP({date_field})) as created_at
            FROM {database}.{table}
        """

    def build_query(self):
        return self.base_query.format(
            date_field=self.date_field,
            database=self.database,
            table=self.table
        )

    def build_key(self, _date, account):
        return self.source_key.format(
            integration=self.integration,
            table=self.adwords_table,
            account=account,
            date_partition=_date,
            file_name=int(time.mktime(datetime.now().timetuple())) * 1000
        )

    @logger(exclude='df')
    def copy_files(self, df):
        if 'account' in df.columns:
            self.__split_by_account(df)
        else:
            date_group = df['created_at'].unique()
            self.__split_by_date(df, date_group, 'default')

    @logger(exclude='df')
    def __split_by_account(self, df):
        accounts = df['account'].unique()
        date_group = df['created_at'].unique()
        _logger.info("m=copy_files, msg=splitting records into accounts and historical data")
        for account in accounts:
            account_df = df.query("account == '{}'".format(account))
            normalized_account = self.__normalize_account_name(account)
            _logger.info("m=copy_files, account={}".format(normalized_account))
            self.__split_by_date(account_df, date_group, normalized_account)

    def __split_by_date(self, df, date_group, account):
        for _date in date_group:
            _logger.info("m=copy_files, msg=splitting into date partition, date='{}'".format(_date))
            new_df = df.query("created_at == '{}'".format(_date))
            formatted_key = self.build_key(_date, account)
            self._move_files_to_raw(new_df, formatted_key)

    @logger
    def __normalize_account_name(self, text, codif='utf-8'):
        remove_accent = unicodedata.normalize('NFKD', text.decode(codif)).encode('ASCII', 'ignore')
        normalized_string = re.sub("^\d+|[\W_]+", "_", remove_accent)
        if normalized_string.startswith("_"):
            return normalized_string[1:].lower()
        return normalized_string.lower()
