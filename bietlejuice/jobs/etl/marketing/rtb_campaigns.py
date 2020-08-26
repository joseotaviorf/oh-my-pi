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
    STATS_TABLE_NAME = "rtb_stats"
    INTEGRATION = 'rtb_ads'
    S3_DATA_LAKE_RAW_RTB_PATH = 'raw/marketing/{}'.format(INTEGRATION)

    def __init__(self, s3_bucket, execution_date, auth, account=None,
                 extra_configs=None):
        super(RtbCampaigns, self).__init__(s3_bucket, execution_date, self.INTEGRATION,
                                           account)
        self.client_id = auth['client_id']
        self.client_secret = auth['client_secret']
        self.S3_STATS_FOLDER = 'stats'
        self.rtb_client = ReportsApiSession(self.client_id, self.client_secret)

    @logger
    def move_rtb_campaigns_to_raw(self):
        for acc in self.get_accounts():
            self._fetch_and_save_stats(acc)

    @logger
    def get_accounts(self):
        accounts = self.rtb_client.get_advertisers()
        if not accounts:
            logger.info('m=get_accounts, msg=No accounts found')
            return []

        return accounts

    @logger(exclude='account')
    def _fetch_and_save_stats(self, account):
        if 'hash' not in account:
            raise ValueError("m=_fetch_and_save_stats, msg=account has no hash and therefore no data!")
        advertiser_hash = account['hash']

        stats_list = self._get_stats(advertiser_hash)
        dpa_stats_list = self._get_dpa_stats(advertiser_hash)
        combined_stats_list = self._combine_stats(stats_list, dpa_stats_list)
        enriched_stats_list = self._enrich_stats(combined_stats_list, account)
        self._save_to_s3(advertiser_hash, self.S3_STATS_FOLDER, enriched_stats_list)

    @logger
    def _get_stats(self, advertiser_hash):
        stats = self.rtb_client.get_rtb_stats(advertiser_hash,
                                              self.execution_date.strftime('%Y-%m-%d'),
                                              self.execution_date.strftime('%Y-%m-%d'),
                                              ['day', 'deviceType', 'subcampaign'])
        return stats

    def _get_dpa_stats(self, advertiser_hash):
        dpa_stats = self.rtb_client.get_dpa_campaign_stats(
            advertiser_hash,
            self.execution_date.strftime('%Y-%m-%d'),
            self.execution_date.strftime('%Y-%m-%d'),
            ['day'])

        for item in dpa_stats:
            item[u'deviceType'] = 'MOBILE'

        return dpa_stats

    def _combine_stats(self, stats, dpa_stats):
        if isinstance(dpa_stats, dict):
            if dpa_stats:
                return stats + [dpa_stats]  # dpa_stats is a dict and is not empty
            else:
                return stats                # dpa_stats is an empty dict

        return stats + dpa_stats            # dpa_stats is a list

    def _enrich_stats(self, stats, account):
        if stats:
            FIELDS_TO_ENRICH = ['hash', 'name', 'currency', 'status']
            for stat in stats:
                for field in FIELDS_TO_ENRICH:
                    field_name = 'account_' + field
                    stat[field_name] = ''
                    if field in account:
                        stat[field_name] = account[field]
        return stats

    @logger(exclude='raw_data')
    def _save_to_s3(self, id_account, entity_name, raw_data):
        if not raw_data:
            logger.info('m=_save_to_s3, msg=There\'s no data to be saved.')
            return

        gz_body = BytesIO()
        for _dict in raw_data:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_dict, ensure_ascii=False)).encode('utf-8'))
                fp.write('\n')

        s3_file_path = '{}/{}/acc={}/dt={}/data.gz'.format(
            self.S3_DATA_LAKE_RAW_RTB_PATH, entity_name, id_account,
            self.execution_date.strftime('%Y-%m-%d'))

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=s3_file_path
        )

        logger.info('m=_save_to_s3, dest={}, msg=Saving RTBHouse data into s3 '
                    'bucket'.format(s3_file_path))

        gz_body.seek(0)
        gz_body.flush()

    @logger
    def move_rtb_stats_to_clean(self):
        c_cols = OrderedDict([
            ('sub_campaign', str),
            ('sub_campaign_hash', str),
            ('cost_attribution_date', str),
            ('device_type', str),
            ('impressions_count', str),
            ('clicks_count', str),
            ('ctr', str),
            ('cost', str),
            ('conversions_count', str),
            ('cr', str),
            ('cpc', str),
            ('ecps', str),
            ('ecc', str),
            ('roas', str),
            ('conversions_value', str),
            ('account_name', str),
            ('account_hash', str),
            ('account_status', str),
            ('account_currency', str)
        ])

        self._move_to_clean(
            table_name='marketing_' + self.STATS_TABLE_NAME,
            sql_file_name='stats.sql',
            r_cols=c_cols,
            c_cols=c_cols
        )

    @logger
    def load_to_staging(self, dw_table_name):
        query = self._get_staging_table_query(dw_table_name)
        query = query.format(date=self.partition_date)
        logger.info("m=load_to_staging, query={}".format(query))

        self._load_to_staging(dw_table_name, query)

    @staticmethod
    @logger
    def _table_type(table_name):
        return table_name.split('_')[0]

    @logger
    def _delete_fact_rows(self, table_name, sk_date):
        delete_query = "DELETE FROM staging.{table_name} " \
                       "WHERE sk_date = {date}".format(table_name=table_name,
                                                       date=sk_date)
        logger.info("m=_delete_fact_rows, query={}".format(delete_query))

        BaseETL.execute_command(
            db_enum=EnumDB.BI_DW,
            command=delete_query,
            commit=True,
            encoding='utf-8'
        )

    @logger
    def _get_staging_table_query(self, table_name):
        """
        Gets the table query to select data from clean tables on Athena
        If it's a fact table and staging is not empty,
        then it'll load only the data of the execution day
        """
        full_load_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR, self.INTEGRATION, table_name))

        if self._table_type(table_name) == 'fact' and not self._is_staging_table_empty(
                table_name):
            sk_date = int(self.execution_date.strftime('%Y%m%d'))
            self._delete_fact_rows(table_name, sk_date)

            daily_load_query = "{} \nWHERE sk_date = {};".format(full_load_query,
                                                                 sk_date)
            return daily_load_query

        return full_load_query

    @logger(exclude="staging_query")
    def _load_to_staging(self, dw_table_name, staging_query, column_types=None):

        logger.info("m=_load_to_staging, schema={}, table_name={}, "
                    "msg=Inserting into dw".format(Marketing.SCHEMA_NAMES['staging'],
                                                   dw_table_name))

        pd_df = self.athena_client.execute_query_and_return_dataframe(sql=staging_query)

        logger.info(
            "m=_load_to_staging, schema={}, table_name={}, msg=Inserting into staging "
            "table".format(
                Marketing.SCHEMA_NAMES['staging'], dw_table_name))

        df_table = petl.fromdataframe(df=pd_df)

        BaseETL.bulk_insert(
            table=df_table,
            table_name='{}.{}'.format(Marketing.SCHEMA_NAMES['staging'], dw_table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=(self._table_type(dw_table_name) != 'dim'),
            commit=True
        )

    @logger
    def load_to_prod(self, table_name):
        self._load_to_prod(table_name)