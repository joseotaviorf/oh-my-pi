import time
from datetime import datetime

from collections import OrderedDict
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR


class GoogleAdsClean(object):
    QUERY_PATH = 'marketing/google_ads/raw_to_clean'
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'
    TABLE_PARTITION_ACCOUNT = '__PARTITION_ACCOUNT__'

    def __init__(self, s3_bucket, execution_date, table, accounts):
        self.s3_bucket = s3_bucket
        self.execution_date = execution_date
        self.table = table
        self.accounts = accounts
        self.partition_date = self.execution_date.strftime('%Y-%m-%d')
        self.athena_client = AthenaClient(self.s3_bucket)

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

        self.__move_to_clean(
            query_path=GoogleAdsClean.QUERY_PATH,
            table_name='keywords',
            sql_file_name='keyword.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def __move_to_clean(self, table_name, sql_file_name, r_cols, c_cols, query_path):
        key = 'clean/marketing/google_ads/{table_name}/acc={acc_partition}/' \
              'created_dt={date_partition}/{file_name}.parquet' \
            .format(
                table_name=table_name,
                acc_partition=self.accounts,
                date_partition=self.partition_date,
                file_name=int(time.mktime(datetime.now().timetuple())) * 1000
            )

        query = BaseETL.get_query_from_file_name(
            '{query_base_dir}/{query_path}/{file_name}'.format(
                query_base_dir=DATALAKE_QUERIES_DIR,
                query_path=query_path,
                file_name=sql_file_name))

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(date=self.execution_date.strftime("%Y-%m-%d"),
                               account=self.accounts),
            raw_columns=r_cols,
            clean_columns=c_cols
        )
