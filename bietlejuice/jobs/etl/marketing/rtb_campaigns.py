import json
from collections import OrderedDict
from gzip import GzipFile
from io import BytesIO

import petl
from qa_python_utils.default_logger import QuintoAndarLogger
from rtbhouse_sdk.reports_api import ReportsApiSession

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.marketing.marketing import Marketing

logger = QuintoAndarLogger('RtbCampaigns')


class RtbCampaigns(Marketing):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'

    def __init__(self, s3_bucket, execution_date, auth, account=None):
        super(RtbCampaigns, self).__init__(s3_bucket, execution_date, 'rtb_campaigns', account)
        self.client_id = 'guilherme.alvares'
        self.client_secret = 'quinto@perf1149'

    def move_rtb_campaigns_to_raw(self):
        self._save_to_s3(self.client_id, self.client_secret)

    def __make_request(self, client_id, client_secret):
        api = ReportsApiSession(client_id, client_secret)
        advertisers = api.get_advertisers()
        stats = api.get_campaign_stats_total(advertisers[0]['hash'], self.execution_date.strftime('%Y-%m-%d'),
                                             self.execution_date.strftime('%Y-%m-%d'), ['day'])
        # stats are the total number of clicks, costs etc
        # advertisers is the information about our campaign (currency, start date etc)
        return stats, advertisers

    def _save_to_s3(self, client_id, client_secret):
        logger.info('m=_save_to_s3, client_id={}'.format(client_id))
        array_stats, array_ads = self.__make_request(client_id, client_secret)

        dic_ads = array_ads[0]
        dic_stats = array_stats[0]
        columns_to_remove = ('ecc', 'roas', 'conversionsValue')

        for k in columns_to_remove:
            dic_stats.pop(k, None)

        columns_to_merge = ('status', 'name', 'url', 'hash', 'currency')
        for j in columns_to_merge:
            dic_stats[j] = dic_ads[j]

        gz_body = BytesIO()
        with GzipFile(fileobj=gz_body, mode='w') as fp:
            fp.write((json.dumps(dic_stats, ensure_ascii=False)).encode('utf-8'))
            fp.write('\n')

        file_suffix = 'raw/marketing/rtb_campaigns/acc=default/dt={}/data.gz'.format(
            self.execution_date.strftime('%Y-%m-%d'))

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )

        gz_body.seek(0)
        gz_body.flush()

    @logger
    def move_rtb_campaigns_to_clean(self):
        r_cols = OrderedDict([
            ('status', str),
            ('hash', str),
            ('name', str),
            ('currency', str),
            ('url', str),
            ('cost_attribution_date', str),
            ('impscount', str),
            ('clickscount', str),
            ('ctr', str),
            ('campaigncost', str),
            ('conversionscount', str),
            ('conversionsrate', str),
            ('cpc', str)
        ])

        c_cols = OrderedDict([
            ('status', str),
            ('hash', str),
            ('name', str),
            ('currency', str),
            ('url', str),
            ('cost_attribution_date', str),
            ('impressions_count', str),
            ('clicks_count', str),
            ('ctr', str),
            ('campaign_cost', str),
            ('conversions_count', str),
            ('conversions_rate', str),
            ('cpc', str)
        ])
        self._move_to_clean(
            table_name='marketing_rtb_campaigns',
            sql_file_name='rtb_campaigns.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )

    # this method calls the query for both fact and dim tables
    # the load table method will select if dim or fact
    def load_to_staging(self, dw_table_name):
        query = self.__load_table(dw_table_name)
        # this line will pass the attributes to the called query and format correctly
        query = query.format(date=self.partition_date, account='default')
        logger.info("m=load_to_staging, query={}".format(query))
        self._load_to_staging(dw_table_name, query)

    def __load_table(self, table_name):
        table_type = table_name.split('_')[0]
        return getattr(self, '_load_{}_to_staging'.format(table_type))(table_name)

    # this is the method that returns the dim query
    def _load_dim_to_staging(self, table_name):
        dim_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR,
                'rtb_campaigns',
                table_name))

        return dim_query

    # this is the method that returns the fact query
    def _load_fact_to_staging(self, table_name):
        int_date = int(self.execution_date.strftime("%Y%m%d"))

        fact_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR,
                'rtb_campaigns',
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

    # this is the final method that load the data from clean to staging, using the
    # queries returned above for both dims and facts

    @logger(exclude="staging_query")
    def _load_to_staging(self, dw_table_name, staging_query):

        logger.info("m=load_to_staging, schema={}, table_name={}, msg=truncating table".format(
            Marketing.SCHEMA_NAMES['staging'], dw_table_name))

        df = self.athena_client.execute_query_and_return_dataframe(sql=staging_query)

        logger.info("m=_load_to_staging, schema={}, table_name={}, msg=inserting into staging table".format(
            Marketing.SCHEMA_NAMES['staging'], dw_table_name))

        df_table = petl.fromdataframe(df=df)

        BaseETL.bulk_insert(
            table=df_table,
            table_name='{}.{}'.format(Marketing.SCHEMA_NAMES['staging'], dw_table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=False,
            commit=True,
        )

    # this is a simple method that select and copy all the table from staging to dw
    # the select is not a separate query, it's just a select distinct * hard-coded
    def load_to_prod(self, table_name):
        self._load_to_prod(table_name)
