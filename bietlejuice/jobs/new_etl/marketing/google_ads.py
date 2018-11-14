from collections import OrderedDict
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import DW_QUERIES_DIR
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
        self.dim_tables = ["dim_google_ads_keyword", "dim_google_ads_ads"]
        self.fact_tables = ["fact_google_ads_daily_cost_attributions"]
        self.datalake_tables = ["marketing_google_ads_keywords", "marketing_google_ads_ads"]

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

    @logger
    def move_ads_to_clean(self):
        r_cols = OrderedDict([
            ('customerid', str),
            ('adgroupid', str),
            ('adgroupname', str),
            ('adtype', str),
            ('campaignid', str),
            ('campaignname', str),
            ('clicks', str),
            ('clicktype', str),
            ('cost', str),
            ('keywordid', str),
            ('date', str),
            ('device', str),
            ('id', str),
            ('impressions', str),
            ('labels', str),
            ('imagecreativename', str),
            ('accountdescriptivename', str),
            ('description', str),
            ('description1', str),
            ('description2', str)
        ])

        c_cols = OrderedDict([
            ('account_id', str),
            ('adgroup_id', str),
            ('adgroup_name', str),
            ('ad_type', str),
            ('campaign_id', str),
            ('campaign_name', str),
            ('clicks', str),
            ('click_type', str),
            ('cost', str),
            ('keyword_id', str),
            ('date', str),
            ('device', str),
            ('ad_id', str),
            ('impressions', str),
            ('labels', str),
            ('image_creative_name', str),
            ('account_name', str),
            ('description', str),
            ('description1', str),
            ('description2', str)
        ])

        self._move_to_clean(
            table_name='marketing_google_ads_ads',
            sql_file_name='ad.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )

    def load_to_pre_staging(self, clean_table, prod_table, accounts):
        self._load_to_pre_staging(clean_table, prod_table, accounts, GoogleAds.COLUMN_TYPE_MAP)

    def load_to_staging(self, dw_table_name):
        query = self.__load_table(dw_table_name)
        self._load_to_staging(dw_table_name, query)

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

        keywords_cte = BaseETL.get_query_from_file_name(
            '{}/staging/marketing/templates/fact_google_ads_keyword.sql'.format(DW_QUERIES_DIR))
        ads_cte = BaseETL.get_query_from_file_name(
            '{}/staging/marketing/templates/fact_google_ads_ad.sql'.format(DW_QUERIES_DIR))
        fact_query = BaseETL.get_query_from_file_name(
            '{}/staging/marketing/fact_google_ads_daily_cost_attributions.sql'.format(DW_QUERIES_DIR))

        empty = self._is_prod_table_empty(table_name)
        if empty:
            logger.info(
                'm=_load_fact_to_staging, schema={}, table_name={}, msg=table already empty'.format(
                    Marketing.SCHEMA_NAMES['prod'], table_name))
        else:
            logger.info(
                'm=_load_fact_to_staging, schema={}, table_name={}, msg=append to table'.format(
                    Marketing.SCHEMA_NAMES['prod'], table_name))

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

        final_query = fact_query.format(
            keywords_cte=keywords_cte,
            ads_cte=ads_cte
        )

        return final_query

    @logger
    def load_to_prod(self, table_name):
        self._load_to_prod(table_name)
