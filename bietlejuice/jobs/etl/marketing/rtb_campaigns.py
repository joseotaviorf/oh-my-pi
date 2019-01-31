import json
from collections import OrderedDict
from gzip import GzipFile
from io import BytesIO

from qa_python_utils.default_logger import QuintoAndarLogger
from rtbhouse_sdk.reports_api import ReportsApiSession

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import DW_QUERIES_DIR
from bietlejuice.jobs.etl.marketing.marketing import Marketing

logger = QuintoAndarLogger('RtbCampaigns')


class RtbCampaigns(Marketing):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'

    def __init__(self, s3_bucket, execution_date, auth, account=None):
        super(RtbCampaigns, self).__init__(s3_bucket, execution_date, 'rtb_campaigns', auth)
        self.client_id = auth['client_id']
        self.client_secret = auth['client_secret']

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
        raw_json_stats, raw_json_ads = self.__make_request(client_id, client_secret)

        gz_body = BytesIO()
        with GzipFile(fileobj=gz_body, mode='w') as fp:
            fp.write((json.dumps(raw_json_stats, ensure_ascii=False)).encode('utf-8'))
            fp.write('\n')

        file_suffix = 'raw/marketing/rtb_campaigns/dt_extraction={}/data.gz'.format(
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
            ('day', str),
            ('impsCount', str),
            ('clicksCount', str),
            ('ctr', str),
            ('campaignCost', str),
            ('conversionsCount', str),
            ('conversionsRate', str),
            ('cpc', str),
            ('ecc', str),
            ('roas', str),
            ('conversionsValue', str),
        ])

        self._move_to_clean(
            table_name='marketing_rtb_campaigns',
            sql_file_name='rtb_campaigns.sql',
            r_cols=r_cols
        )

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
