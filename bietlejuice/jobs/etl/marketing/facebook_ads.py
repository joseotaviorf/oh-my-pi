from collections import OrderedDict

from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import DW_QUERIES_DIR
from bietlejuice.jobs.etl.marketing.marketing import Marketing

logger = QuintoAndarLogger('FacebookAds')


class FacebookAds(Marketing):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'
    TABLE_PARTITION_ACCOUNT = '__PARTITION_ACCOUNT__'

    COLUMN_TYPE_MAP = {
        'ad_id': long,
        'account_id': long,
        'campaign_id': long,
        'adset_id': long,
        'reach': int,
        'clicks': int,
        'spend': float,
        'link_clicks': int
    }

    def __init__(self, s3_bucket, execution_date, accounts, auth=None):
        super(FacebookAds, self).__init__(s3_bucket, execution_date, 'facebook_ads', accounts)

    @logger
    def move_ads_to_clean(self):
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
            ('date_stop', str),
            ('inline_link_clicks', str)
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
            ('date_stop', str),
            ('link_clicks', str)
        ])

        self._move_to_clean(
            table_name='marketing_facebook_ads',
            sql_file_name='ads_insights.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def load_to_pre_staging(self, clean_table, prod_table, accounts):
        self._load_to_pre_staging(clean_table, prod_table, accounts, FacebookAds.COLUMN_TYPE_MAP)

    @logger
    def load_to_staging(self, dw_table_name):
        query = self.__load_table(dw_table_name)
        logger.info("m=load_to_staging, query={}".format(query))
        self._load_to_staging(dw_table_name, query)

    @logger
    def __load_table(self, table_name):
        table_type = table_name.split('_')[0]
        return getattr(self, '_load_{}_to_staging'.format(table_type))(table_name)

    @logger
    def _load_dim_to_staging(self, table_name):
        dim_query = BaseETL.get_query_from_file_name(
            '{}/staging/marketing/{}.sql'.format(
                DW_QUERIES_DIR,
                table_name))

        return dim_query

    @logger
    def _load_fact_to_staging(self, table_name):
        int_date = int(self.execution_date.strftime("%Y%m%d"))

        fact_query = BaseETL.get_query_from_file_name(
            '{}/staging/marketing/{}.sql'.format(
                DW_QUERIES_DIR,
                table_name))

        empty = self._is_prod_table_empty(table_name)
        if empty:
            logger.info(
                'm=load_to_staging, schema={}, table_name={}, msg=table already empty'.format(
                    Marketing.SCHEMA_NAMES['prod'], table_name))
        else:
            delete_query = "DELETE FROM {schema}.{table_name} where sk_date = {date_partition}"

            BaseETL.execute_command(
                command=delete_query.format(
                    schema=Marketing.SCHEMA_NAMES['staging'],
                    table_name=table_name,
                    date_partition=int_date),
                db_enum=EnumDB.BI_DW,
                encoding='utf-8',
                commit=True
            )

            BaseETL.execute_command(
                command=delete_query.format(
                    schema=Marketing.SCHEMA_NAMES['prod'],
                    table_name=table_name,
                    date_partition=int_date),
                db_enum=EnumDB.BI_DW,
                encoding='utf-8',
                commit=True
            )

        return fact_query

    @logger
    def load_to_prod(self, table_name):
        self._load_to_prod(table_name)
