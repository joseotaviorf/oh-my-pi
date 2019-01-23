import json
from ast import literal_eval
from gzip import GzipFile
from io import BytesIO

import requests
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import DW_QUERIES_DIR
from bietlejuice.jobs.etl.marketing.marketing import Marketing

logger = QuintoAndarLogger('CriteoCampaigns')


class CriteoCampaigns(Marketing):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'

    COLUMN_TYPE_MAP = {
        'marketing_criteo_campaigns': {
            'advertiser_name': str,
            'campaign_id': int,
            'campaign_name': str,
            'day': int,
            'currency': str,
            'clicks': int,
            'cost': float,
            'impressions': int,
            'Sales': int,
            'Audiencia': float,
            'Revenue': int,
            'comp_win': float,
            'cpc': float,

        }
    }

    def __init__(self, s3_bucket, execution_date, client_id=None, client_secret=None):
        super(CriteoCampaigns, self).__init__(s3_bucket, execution_date, 'criteo_campaigns', client_id, client_secret)

    @logger
    def transfer_criteo_to_raw(self, client_id, client_secret):
        self.__save_to_s3(client_id, client_secret)

    @logger
    def __get_token(self, client_id, client_secret):
        headers = {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
        }

        data = {
            'client_id': client_id,
            'client_secret': client_secret,
            'grant_type': 'client_credentials'
        }

        response = requests.post('https://api.criteo.com/marketing/oauth2/token', headers=headers, data=data)
        dic = literal_eval(response.text)
        auth_token = 'Bearer ' + dic['access_token']
        return auth_token

    @logger
    def __make_request(self, client_id, client_secret):
        auth_token = self.__get_token(client_id, client_secret)

        headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/octet-stream',
            'Authorization': auth_token,
        }
        data = '{"reportType": "CampaignPerformance", "startDate": {}, \
                "endDate": {},"dimensions": ["CampaignId", "Day"], \
                "metrics": ["Clicks", "Displays", "Audience", "AdvertiserCost","SalesAllPc",\
                "RevenueGeneratedPc", "OverallCompetitionWin", "ECpc"], "format": "json", \
                "timezone": "GMT"}'.format("2019-01-10T12:10:20.544Z", "2019-01-16T12:10:20.544Z")

        response = requests.post('https://api.criteo.com/marketing/v1/statistics', headers=headers, data=data)
        return response.text

    @logger
    def __save_to_s3(self, client_id, client_secret):
        raw_json_data = self.__make_request(client_id, client_secret)

        gz_body = BytesIO()
        with GzipFile(fileobj=gz_body, mode='w') as fp:
            fp.write((json.dumps(raw_json_data, ensure_ascii=False)).encode('utf-8'))
            fp.write('\n')

        file_suffix = 'raw/marketing/criteo_campaigns/dt_extraction={}/data.gz'.format(
            self.execution_date.strftime('%Y-%m-%d'))

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )

        # clear obj allocation
        # only flushing does not clear the buffer
        gz_body.seek(0)
        gz_body.flush()

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
