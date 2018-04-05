from jobs.new_etl.amplitude.growth_users import GrowthUsers
from qa_python_utils.default_logger import logger


class ActiveUsers(GrowthUsers):
    TABLE_NAME_PREFIX = 'amplitude_active_users'

    @logger
    def __init__(self, s3_bucket):
        super(ActiveUsers, self).__init__(measure='active_users', s3_bucket=s3_bucket)

    @staticmethod
    @logger(exclude='df')
    def df_to_dw(df, period, _filter=None):
        GrowthUsers.df_to_dw(df, '{}{}_{}'.format(ActiveUsers.TABLE_NAME,
                                                  '_{}'.format(_filter) if _filter is not None else '', period))

    @staticmethod
    @logger
    def truncate_table(period=None):
        GrowthUsers.truncate_table(
            '{}_{}'.format(ActiveUsers.TABLE_NAME_PREFIX,
                           period) if period is not None else ActiveUsers.TABLE_NAME_PREFIX)

    @logger
    def save_to_table(self, _filter, period):
        ActiveUsers.truncate_table(period)
        self.append_to_table(_filter=_filter, period=period)

    @logger
    def append_to_table(self, _filter, period):
        self.__append(_filter=_filter, period=period, prefix=self._get_all_dates_query())
        self.__append(_filter=_filter, period=period, prefix=self._get_current_date_query())

    @logger
    def __append(self, _filter, period, prefix):
        df = self.get_df(prefix=prefix, suffix=self._get_suffix_query(period=period))
        ActiveUsers.df_to_dw(df=df, period=period, filter=_filter)
