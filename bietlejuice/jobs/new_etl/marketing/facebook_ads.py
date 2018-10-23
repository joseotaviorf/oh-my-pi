from collections import OrderedDict
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.new_etl.marketing.marketing import Marketing

logger = QuintoAndarLogger('FacebookAds')


class FacebookAds(Marketing):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'
    TABLE_PARTITION_ACCOUNT = '__PARTITION_ACCOUNT__'

    COLUMN_TYPE_MAP = {
        'fact_google_ads_daily_keywords': {
            'sk_keyword': long,
            'account_id': long,
            'campaign_id': long,
            'adgroup_id': long,
            'mobile_clicks': int,
            'tablet_clicks': int,
            'computer_clicks': int,
            'total_clicks': int,
            'total_cost': float,
            'impressions': int,
            'sk_date': int
        },
        'dim_google_ads_keyword': {
            'sk_keyword': long,
            'keyword_id': long
        }
    }

    def __init__(self, s3_bucket, execution_date, account=None):
        super(FacebookAds, self).__init__(s3_bucket, execution_date, 'facebook_ads', account)

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
            table_name='ads_insights',
            sql_file_name='ads_insights.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )

    def load_to_pre_staging(self, clean_table, prod_table, accounts):
        self._load_to_pre_staging(clean_table, prod_table, accounts, FacebookAds.COLUMN_TYPE_MAP)
