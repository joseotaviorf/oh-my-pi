from bietlejuice.jobs.new_etl.amplitude.growth_users import GrowthUsers
from qa_python_utils.default_logger import logger


class OwnerLandingViews(GrowthUsers):
    TABLE_NAME = 'amplitude_owner_landing_views'

    @logger
    def __init__(self, s3_bucket):
        super(OwnerLandingViews, self).__init__(measure='owner_landing_views', s3_bucket=s3_bucket)

    @staticmethod
    @logger(exclude='df')
    def df_to_dw(df):
        GrowthUsers._df_to_dw(df, OwnerLandingViews.TABLE_NAME)

    @staticmethod
    @logger
    def truncate_table():
        GrowthUsers._truncate_table(OwnerLandingViews.TABLE_NAME)

    @logger
    def append_to_table(self, _filter):
        self.__append(_filter=_filter, prefix=self.all_dates_query)
        self.__append(_filter=_filter, prefix=self.current_date_query)

    @logger
    def __append(self, _filter, prefix):
        df = self.get_df(prefix=prefix, suffix=self.suffix_query)
        OwnerLandingViews.df_to_dw(df=df)
