import time
from datetime import datetime

from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.new_etl.stitch.stitch_transfer_raw import StitchTransferRaw


class FacebookAdsTransferRaw(StitchTransferRaw):
    @logger
    def __init__(self, bucket, execution_date, integration, database, table, date_field, account):
        super(FacebookAdsTransferRaw, self).__init__(bucket, execution_date, integration, database, table, date_field)
        self.account = account
        self.facebook_table = self.table
        self.table = "{}_{}_{}".format(self.integration, self.account, self.table)

    @logger
    def __build_facebook_key(self, _date):
        return "raw/market_cost/{integration}/{table}/acc={account}/dt={date_partition}/{file_name}.jsonl".format(
            integration=self.integration,
            table=self.facebook_table,
            account=self.account,
            date_partition=_date,
            file_name=int(time.mktime(datetime.now().timetuple())) * 1000
        )

    @logger
    def move_facebook_files(self):
        df = self._fetch_data(self._build_query())
        date_group = df['created_at'].unique()
        _logger.info("m=move_facebook_files, msg=splitting records into historical data")
        for _date in date_group:
            new_df = df.query("created_at == '{}'".format(_date))
            formatted_key = self.__build_facebook_key(_date)
            _logger.info("m=move_facebook_files, msg=group records by date, date='{}'".format(_date))
            self._move_files_to_raw(new_df, formatted_key)
