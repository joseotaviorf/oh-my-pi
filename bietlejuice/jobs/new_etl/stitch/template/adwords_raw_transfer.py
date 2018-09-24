import re
import time
import unicodedata
from datetime import datetime

from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.new_etl.stitch.stitch_transfer_raw import StitchTransferRaw


class AdWordsTransferRaw(StitchTransferRaw):
    def __init__(self, bucket, execution_date, integration, database, table, date_field):
        super(AdWordsTransferRaw, self).__init__(bucket, execution_date, integration, database, table, date_field)
        self.adwords_table = self.table
        self.table = "{}_{}".format(self.integration, self.table)

    def __build_adwords_key(self, account, _date):
        return self.source_key.format(
            integration=self.integration,
            table=self.adwords_table,
            account=account,
            date_partition=_date,
            file_name=int(time.mktime(datetime.now().timetuple())) * 1000
        )

    @logger
    def __normalize_account_name(self, text, codif='utf-8'):
        remove_accent = unicodedata.normalize('NFKD', text.decode(codif)).encode('ASCII', 'ignore')
        normalized_string = re.sub("^\d+|[\W_]+", "_", remove_accent)
        if normalized_string.startswith("_"):
            return normalized_string[1:].lower()
        return normalized_string.lower()

    @logger
    def move_adwords_files(self):
        df = self._fetch_data(self._build_query())

        accounts = df['account'].unique()
        date_group = df['created_at'].unique()

        _logger.info("m=move_adwords_files, msg=splitting records into accounts and historical data")
        for account in accounts:
            account_df = df.query("account == '{}'".format(account))
            normalized_account = self.__normalize_account_name(account)
            _logger.info("m=move_adwords_files, account={}".format(normalized_account))
            for _date in date_group:
                _logger.info("m=move_adwords_files, msg=splitting into date partition, date='{}'".format(_date))
                new_df = account_df.query("created_at == '{}'".format(_date))
                formatted_key = self.__build_adwords_key(normalized_account, _date)
                self._move_files_to_raw(new_df, formatted_key)
