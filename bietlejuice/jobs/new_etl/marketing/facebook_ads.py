from collections import OrderedDict
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.marketing.marketing import Marketing


class FacebookAds(Marketing):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'
    TABLE_PARTITION_ACCOUNT = '__PARTITION_ACCOUNT__'

    def __init__(self, s3_bucket, execution_date, account):
        super(FacebookAds, self).__init__(s3_bucket, execution_date, account, 'facebook_ads')

    @logger
    def move_ads_insights_to_clean(self):
        r_cols = OrderedDict([
            ('account_id', str),
            ('account_name', str),
            ('ad_id', str),
            ('ad_name', str),
            ('adset_id', str),
            ('adset_name', str),
            ('campaign_id', str),
            ('campaign_name', str),
            ('reach', str),
            ('impressions', str),
            ('clicks', str),
            ('spend', str),
            ('impression_device', str),
            ('date_start', str),
            ('date_stop', str)
        ])

        c_cols = OrderedDict([
            ('account_id', str),
            ('account_name', str),
            ('ad_id', str),
            ('ad_name', str),
            ('adset_id', str),
            ('adset_name', str),
            ('campaign_id', str),
            ('campaign_name', str),
            ('reach', str),
            ('impressions', str),
            ('clicks', str),
            ('spend', str),
            ('impression_device', str),
            ('date_start', str),
            ('date_stop', str)
        ])

        self._move_to_clean(
            query_path=self.query_path,
            table_name='ads_insights',
            sql_file_name='ads_insights.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )
