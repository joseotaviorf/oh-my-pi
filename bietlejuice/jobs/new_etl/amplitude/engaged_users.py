from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl.amplitude import QUERIES_DIR
from bietlejuice.jobs.new_etl.amplitude.growth_users import GrowthUsers
from qa_python_utils.default_logger import logger


class EngagedUsers(GrowthUsers):
    TABLE_NAME = 'amplitude_engaged_users'

    @logger
    def __init__(self, s3_bucket):
        super(EngagedUsers, self).__init__(measure='engaged_users', s3_bucket=s3_bucket)

    @staticmethod
    @logger(exclude='df')
    def df_to_dw(df):
        GrowthUsers.df_to_dw(df, EngagedUsers.TABLE_NAME)

    @staticmethod
    @logger
    def truncate_table():
        GrowthUsers.truncate_table(EngagedUsers.TABLE_NAME)

    @logger
    def append_to_table(self, _filter):
        self.__append(_filter=_filter, prefix=self.all_dates_query)
        self.__append(_filter=_filter, prefix=self.current_date_query)

    @logger
    def __append(self, _filter, prefix):
        middle_query = BaseETL.get_query_from_file_name(
            '{}/engaged_users/middle_{}.sql'.format(QUERIES_DIR, _filter))

        df = self.get_df(prefix=prefix,
                         middle=middle_query,
                         suffix=self.suffix_query)

        EngagedUsers.df_to_dw(df=df)
