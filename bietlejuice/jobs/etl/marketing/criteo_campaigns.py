import json
from ast import literal_eval
from collections import OrderedDict
from gzip import GzipFile
from io import BytesIO

import petl
import requests
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.marketing.marketing import Marketing

logger = QuintoAndarLogger('CriteoCampaigns')


class CriteoCampaigns(Marketing):
    TABLE_PARTITION_DATE = '__PARTITION_DATE__'

    def __init__(self, s3_bucket, execution_date, auth, account=None):
        super(CriteoCampaigns, self).__init__(s3_bucket, execution_date, 'criteo_campaigns', account)
        self.client_id = auth['client_id']
        self.client_secret = auth['client_secret']

    # wrapper method
    def move_criteo_campaigns_to_raw(self):
        self._save_to_s3(self.client_id, self.client_secret)

    # get token from criteo, this has to be done every request, since the token expires in 5 minutes
    def __get_token(self, client_id, client_secret):
        logger.info('m=__get_token')
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
        # this is hard coded because criteo expects this word before the access token string
        auth_token = 'Bearer ' + dic['access_token']
        return auth_token

    # make te request from criteo api, extracting the data from the day we want
    # you must pass the token generated before and the variables you want to compute
    def __make_request(self, client_id, client_secret):
        logger.info('m=__make_request')
        auth_token = self.__get_token(client_id, client_secret)
        # the header contains the auth token and must be passed to the request
        headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/octet-stream',
            'Authorization': auth_token,
        }
        # the body must be passed to the API call with the wanted columns and date time
        body = {'reportType': 'CampaignPerformance',
                'startDate': '{}'.format(self.execution_date.strftime('%Y-%m-%d') + 'T00:00:59.000Z'),
                'endDate': '{}'.format(self.execution_date.strftime('%Y-%m-%d') + 'T23:59:00.000Z'),
                'dimensions': ['CampaignId', 'Day'],
                'metrics': ['Clicks', 'Displays', 'Audience', 'AdvertiserCost', 'SalesAllPc', 'RevenueGeneratedPc',
                            'OverallCompetitionWin', 'ECpc'],
                'format': 'json', 'timezone': 'GMT'}

        data = json.dumps(body)

        # this is a simple try except in case the request fails
        try:
            response = requests.post('https://api.criteo.com/marketing/v1/statistics', headers=headers, data=data)
            loaded = json.loads(response.text)
            response_without_total = loaded["Rows"]
            # The json returned by the API has 2 tables ("Total" and "Rows"), one with all the necessary vars,
            # and the other with just the sum of everything. This way, we're sending only the necessary table to DL
            return response_without_total
        except requests.exceptions.RequestException as e:
            logger.error('m=__make_request, error message={}'.format(e))

    # this method saves the json as compacted gz and also breaks every row in lines, so that Athena will compute
    def _save_to_s3(self, client_id, client_secret):

        logger.info('m=_save_to_s3, client_id={}'.format(client_id))
        raw_dict_data = self.__make_request(client_id, client_secret)

        gz_body = BytesIO()
        # this loop iterates over every row and writes a json where every row is separated by line break
        for _dict in raw_dict_data:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_dict, ensure_ascii=False)).encode('utf-8'))
                fp.write('\n')

        file_suffix = 'raw/marketing/criteo_campaigns/acc=default/dt={}/data.gz'.format(
            self.execution_date.strftime('%Y-%m-%d'))

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )
        # always flush after using!
        gz_body.seek(0)
        gz_body.flush()

    # this method maps the table as it is from criteo and makes a clean one with better var names
    # also, it runs the query raw-to-clean

    @logger
    def move_criteo_campaigns_to_clean(self):
        r_cols = OrderedDict([
            ('advertiser name', str),
            ('campaign id', str),
            ('campaign name', str),
            ('cost_attribution_date', str),
            ('currency', str),
            ('clicks', str),
            ('impressions', str),
            ('audience', str),
            ('cost', str),
            ('all sales', str),
            ('revenue', str),
            ('comp. win', str),
            ('cpc', str)
        ])

        c_cols = OrderedDict([
            ('advertiser_name', str),
            ('campaign_id', str),
            ('campaign_name', str),
            ('cost_attribution_date', str),
            ('currency', str),
            ('clicks', str),
            ('impressions', str),
            ('audience', str),
            ('cost', str),
            ('all_sales', str),
            ('revenue', str),
            ('composition_win', str),
            ('cpc', str)
        ])

        self._move_to_clean(
            table_name='marketing_criteo_campaigns',
            sql_file_name='criteo_campaigns.sql',
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
                'criteo_campaigns',
                table_name))

        return dim_query

    # this is the method that returns the fact query
    def _load_fact_to_staging(self, table_name):
        int_date = int(self.execution_date.strftime("%Y%m%d"))

        fact_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR,
                'criteo_campaigns',
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
