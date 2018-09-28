import time
from datetime import datetime

from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.new_etl.stitch.stitch_transfer_raw_template import StitchTransferRawTemplate


class FacebookAdsTransferRaw(StitchTransferRawTemplate):

    @logger
    def __init__(self, bucket, execution_date, integration, database, table, date_field, accounts):
        super(FacebookAdsTransferRaw, self).__init__(bucket, execution_date, integration, database, table, date_field)
        self.accounts = accounts
        self.facebook_table = ""
        self.base_query = """
            SELECT '{account}' as account, *, DATE(FROM_ISO8601_TIMESTAMP({date_field})) as created_at
            FROM {database}.{table}
        """

    def build_query(self):
        queries = []
        for account in self.accounts:
            table = "{}_{}_{}".format(self.integration, account, self.table)
            formatted_query = self.base_query.format(
                account=account,
                date_field=self.date_field,
                database=self.database,
                table=table
            )
            queries.append(formatted_query)
        return "union all".join(queries)

    def build_key(self, _date, account):
        return "raw/market_cost/{integration}/{table}/acc={account}/dt={date_partition}/{file_name}.jsonl".format(
            integration=self.integration,
            table=self.table,
            account=account,
            date_partition=_date,
            file_name=int(time.mktime(datetime.now().timetuple())) * 1000
        )

    def copy_files(self, df):
        date_group = df['created_at'].unique()
        _logger.info("m=copy_files, msg=splitting records into historical data")

        for account in self.accounts:
            account_df = df.query("account == '{}'".format(account))
            _logger.info("m=copy_files, account={}".format(account))
            for _date in date_group:
                new_df = account_df.query("created_at == '{}'".format(_date))
                formatted_key = self.build_key(_date, account)
                _logger.info("m=copy_files, msg=group records by account and date, date='{}'".format(_date))
                self._move_files_to_raw(new_df, formatted_key)

