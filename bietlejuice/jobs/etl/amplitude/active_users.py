from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.amplitude.growth_amplitude import GrowthAmplitude

logger = QuintoAndarLogger('ActiveUsers')


class ActiveUsers(GrowthAmplitude):
    TABLE_NAME = 'amplitude_active_users'

    @logger
    def __init__(self, s3_bucket):
        super(ActiveUsers, self).__init__(measure='active_users', s3_bucket=s3_bucket)

    @staticmethod
    @logger(exclude='df')
    def df_to_dw(df):
        GrowthAmplitude._df_to_dw(df, ActiveUsers.TABLE_NAME)

    @staticmethod
    @logger
    def truncate_table():
        GrowthAmplitude._truncate_table(ActiveUsers.TABLE_NAME)

    @logger
    def append_to_table(self, _filter):
        self.__append(_filter=_filter, prefix=self.all_dates_query)
        self.__append(_filter=_filter, prefix=self.current_date_query)

    @logger
    def __append(self, _filter, prefix):
        df = self.get_df(prefix=prefix, suffix=self.suffix_query)
        ActiveUsers.df_to_dw(df=df)
