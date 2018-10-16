from collections import OrderedDict
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.marketing.marketing import Marketing


class GoogleAds(Marketing):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'
    TABLE_PARTITION_ACCOUNT = '__PARTITION_ACCOUNT__'

    def __init__(self, s3_bucket, execution_date, account):
        super(GoogleAds, self).__init__(s3_bucket, execution_date, account, 'google_ads')

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
            ('keyword_match_type', str),
            ('labels', str),
            ('criteria', str),
            ('account_descriptive_name', str)
        ])

        self._move_to_clean(
            query_path=self.query_path,
            table_name='marketing_googleads_keywords',
            sql_file_name='keyword.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )
