from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.amplitude.growth_amplitude import GrowthAmplitude

logger = QuintoAndarLogger('EngagedUsers')


class EngagedUsers(GrowthAmplitude):
    TABLE_NAME = 'amplitude_engaged_users'

    @logger
    def __init__(self, s3_bucket):
        super(EngagedUsers, self).__init__(measure='engaged_users', s3_bucket=s3_bucket)

    @staticmethod
    @logger(exclude='df')
    def df_to_dw(df):
        GrowthAmplitude._df_to_dw(df, EngagedUsers.TABLE_NAME)

    @staticmethod
    @logger
    def truncate_table():
        GrowthAmplitude._truncate_table(EngagedUsers.TABLE_NAME)

    @logger
    def append_to_table(self, _filter):
        self.__append(_filter=_filter, prefix=self.all_dates_query)
        self.__append(_filter=_filter, prefix=self.current_date_query)

    @logger
    def __append(self, _filter, prefix):
        middle_query = BaseETL.get_query_from_file_name(
            '{}/engaged_users/middle_{}.sql'.format(GrowthAmplitude.QUERIES_DIR, _filter))

        df = self.get_df(prefix=prefix,
                         middle=middle_query,
                         suffix=self.suffix_query)

        EngagedUsers.df_to_dw(df=df)
