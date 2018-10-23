from collections import OrderedDict
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.new_etl.marketing.marketing import Marketing

logger = QuintoAndarLogger('GoogleAds')


class GoogleAds(Marketing):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'
    TABLE_PARTITION_ACCOUNT = '__PARTITION_ACCOUNT__'

    COLUMN_TYPE_MAP = {
        'account_id': long,
        'campaign_id': long,
        'adgroup_id': long,
        'clicks': int,
        'cost': float,
        'impressions': int,
        'keyword_id': long
    }

    def __init__(self, s3_bucket, execution_date, account=None):
        super(GoogleAds, self).__init__(s3_bucket, execution_date, 'google_ads', account)

    @logger
    def move_keywords_to_clean(self):
        r_cols = OrderedDict([
            ('customerid', str),
            ('adgroupid', str),
            ('adgroupname', str),
            ('campaignid', str),
            ('campaignname', str),
            ('clicks', str),
            ('clicktype', str),
            ('cost', str),
            ('date', str),
            ('device', str),
            ('id', str),
            ('impressions', str),
            ('keywordmatchtype', str),
            ('labels', str),
            ('criteria', str),
            ('accountdescriptivename', str)
        ])

        c_cols = OrderedDict([
            ('account_id', str),
            ('adgroup_id', str),
            ('adgroup_name', str),
            ('campaign_id', str),
            ('campaign_name', str),
            ('clicks', str),
            ('click_type', str),
            ('cost', str),
            ('date', str),
            ('device', str),
            ('keyword_id', str),
            ('impressions', str),
            ('match_type', str),
            ('labels', str),
            ('criteria', str),
            ('account_name', str)
        ])

        self._move_to_clean(
            table_name='marketing_google_ads_keywords',
            sql_file_name='keyword.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )

    def load_to_pre_staging(self, clean_table, prod_table, accounts):
        self._load_to_pre_staging(clean_table, prod_table, accounts, GoogleAds.COLUMN_TYPE_MAP)
