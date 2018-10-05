from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl.amplitude import QUERIES_DIR
from bietlejuice.jobs.new_etl.amplitude.growth_amplitude import GrowthAmplitude

logger = QuintoAndarLogger('ListingsWithPageViews')


class ListingsWithPageViews(GrowthAmplitude):
    TABLE_NAME = 'amplitude_listings_unique_page_views'

    @logger
    def __init__(self, s3_bucket):
        super(ListingsWithPageViews, self).__init__(measure='listings_unique_page_views', s3_bucket=s3_bucket)

    @staticmethod
    @logger(exclude='df')
    def df_to_dw(df):
        GrowthAmplitude._df_to_dw(df, ListingsWithPageViews.TABLE_NAME)

    @staticmethod
    @logger
    def truncate_table():
        GrowthAmplitude._truncate_table(ListingsWithPageViews.TABLE_NAME)

    @logger
    def append_to_table(self, _filter):
        self.__append(_filter=_filter, prefix=self.all_dates_query)
        self.__append(_filter=_filter, prefix=self.current_date_query)

    @logger
    def __append(self, _filter, prefix):
        middle_query = BaseETL.get_query_from_file_name(
            '{}/listings_unique_page_views/middle_{}.sql'.format(QUERIES_DIR, _filter))

        df = self.get_df(prefix=prefix,
                         middle=middle_query,
                         suffix=self.suffix_query)

        ListingsWithPageViews.df_to_dw(df=df)
