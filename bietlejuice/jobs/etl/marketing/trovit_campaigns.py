import time
from collections import OrderedDict
from copy import deepcopy

from qa_python_utils.aws.batch import BatchClient
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.marketing import Marketing

logger = QuintoAndarLogger('TrovitCampaigns')


class TrovitCampaigns(Marketing):

    def __init__(self, s3_bucket, execution_date, auth, account=None):
        super(TrovitCampaigns, self).__init__(s3_bucket, execution_date,
                                              'trovit_campaigns', account)

    @logger
    def move_trovit_campaigns_to_raw(self):
        logger.info('m={}, msg={}'.format('move_trovit_campaigns_to_raw', 'Starting job...'))
        start_date = self.execution_date.strftime(
            '%Y-%m-%d')
        batch_client = BatchClient()
        job_name = 'scrap-trovit-data'
        job_queue = 'scrap-marketing-data'
        r = batch_client.start_batch_job(
            job_name=job_name,
            job_queue=job_queue,
            job_definition='scrap-marketing-data:1',
            command=['scrapy', 'crawl', 'trovit',
                     '-a', 'start_date={}'.format(start_date),
                     '-a', 'end_date={}'.format(start_date),
                     '-o', 's3://5a-datalake/raw/marketing/trovit_campaigns/acc={}/dt={}/data.gz'.format(self.account,
                                                                                                         start_date)]
        )

        while not (batch_client.get_job_info_by_id(r.get('jobId')).get('status') in ('SUCCEEDED', 'FAILED')):
            time.sleep(30)

        final_status = batch_client.get_job_info_by_id(r.get('jobId')).get('status')

        if final_status == 'FAILED':
            raise RuntimeError('m={}, msg={}'.format('scrap_trovit_data', 'Job {} failed.'.format(r.get('jobName'))))

        logger.info('m={}, msg=Job {} ended successfully'.format('scrap_trovit_data', r.get('jobName')))

    @logger
    def move_marketing_trovit_campaigns_to_clean(self):
        r_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('clicks', str),
            ('desktop_cost', str),
            ('mobile_cost', str),
            ('total_cost', str),
            ('curr_date', str)
        ])

        c_cols = deepcopy(r_cols)

        self._move_to_clean(
            table_name='marketing_trovit_campaigns',
            sql_file_name='trovit_campaigns.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )

    # this method calls the query for both fact and dim tables
    # the load table method will select if dim or fact
    def load_to_staging(self, dw_table_name):
        query = self.__load_table(dw_table_name)
        # this line will pass the attributes to the called query and format
        # correctly
        query = query.format(date=self.partition_date, account='default')
        logger.info("m=load_to_staging, query={}".format(query))
        self._load_to_staging(dw_table_name, query)

    def __load_table(self, table_name):
        table_type = table_name.split('_')[0]
        return getattr(self, '_load_{}_to_staging'.format(table_type))(
            table_name)

    # this is the method that returns the dim query
    def _load_dim_to_staging(self, table_name):
        dim_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR,
                'trovit_campaigns',
                table_name))

        return dim_query

    # this is the method that returns the fact query
    def _load_fact_to_staging(self, table_name):
        int_date = int(self.execution_date.strftime("%Y%m%d"))

        fact_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR,
                'trovit_campaigns',
                table_name))

        empty = self._is_prod_table_empty(table_name)
        if empty:
            logger.info(
                'm=load_to_staging, schema={}, table_name={}, msg=table '
                'already empty'.format(
                    Marketing.SCHEMA_NAMES['prod'], table_name))
        else:
            delete_query = "DELETE FROM {schema}.{table_name} where " \
                           "sk_date = " \
                           "{date_partition}"

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

    def load_to_prod(self, table_name):
        self._load_to_prod(table_name)
