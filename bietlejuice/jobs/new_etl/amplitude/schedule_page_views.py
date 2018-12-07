from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl.amplitude.growth_amplitude import GrowthAmplitude

logger = QuintoAndarLogger('SchedulePageViews')


class SchedulePageViews(GrowthAmplitude):
    TABLE_NAME = 'amplitude_schedule_page_views'

    @logger
    def __init__(self, s3_bucket):
        super(SchedulePageViews, self).__init__(measure='schedule_page_views', s3_bucket=s3_bucket)

    @staticmethod
    @logger(exclude='df')
    def df_to_dw(df):
        GrowthAmplitude._df_to_dw(df, SchedulePageViews.TABLE_NAME)

    @staticmethod
    @logger
    def truncate_table():
        GrowthAmplitude._truncate_table(SchedulePageViews.TABLE_NAME)

    @logger
    def append_to_table(self, _filter):
        self.__append(_filter=_filter, prefix=self.all_dates_query)
        self.__append(_filter=_filter, prefix=self.current_date_query)

    @logger
    def __append(self, _filter, prefix):
        middle_query = BaseETL.get_query_from_file_name(
            '{}/{}/middle_{}.sql'.format(GrowthAmplitude.QUERIES_DIR, self.measure, _filter))

        df = self.get_df(prefix=prefix,
                         middle=middle_query,
                         suffix=self.suffix_query)

        SchedulePageViews.df_to_dw(df=df)
