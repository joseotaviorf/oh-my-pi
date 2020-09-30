import time
from collections import OrderedDict

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.marketing.marketing import Marketing
from qa_python_utils.aws.batch import BatchClient
from qa_python_utils.default_logger import QuintoAndarLogger

logger = QuintoAndarLogger('LifullCampaigns')


class LifullCampaigns(Marketing):
    def __init__(self, s3_bucket, execution_date, auth, account=None,
                 extra_configs=None):
        super(LifullCampaigns, self).__init__(s3_bucket, execution_date,
                                              'lifull_campaigns', account)
        self.group_names = ['trovit', 'mitula']

    @logger
    def move_lifull_campaigns_to_raw(self):
        logger.info('m={}, msg={}'.format('move_lifull_campaigns_to_raw', 'Starting job...'))
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
                     '-o', 's3://{}/raw/marketing/lifull_campaigns/acc={}/dt={}/data.gz'.format(self.s3_bucket, 'default', start_date)]
        )

        while not (batch_client.get_job_info_by_id(r.get('jobId')).get('status') in ('SUCCEEDED', 'FAILED')):
            time.sleep(30)

        final_status = batch_client.get_job_info_by_id(r.get('jobId')).get('status')

        if final_status == 'FAILED':
            raise RuntimeError('m={}, msg={}'.format('scrap_trovit_data', 'Job {} failed.'.format(r.get('jobName'))))

        logger.info('m={}, msg=Job {} ended successfully'.format('scrap_trovit_data', r.get('jobName')))

    @logger
    def move_marketing_lifull_campaigns_to_clean(self, group_name):
        r_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('clicks', str),
            ('desktop_cost', str),
            ('mobile_cost', str),
            ('total_cost', str),
            ('curr_date', str)
        ])

        self._move_to_clean(
            table_name='marketing_lifull_campaigns',
            sql_file_name='lifull_campaigns.sql',
            group_name=group_name,
            r_cols=r_cols,
            c_cols=r_cols
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean(self, table_name, sql_file_name, group_name, r_cols, c_cols=None, validate_data=False):
        key = 'clean/marketing/{integration}/{table_name}/acc={acc_partition}/group_name={group_name}/' \
              'dt_created={date_partition}/{file_name}.parquet' \
            .format(integration=self.integration,
                    table_name=table_name,
                    acc_partition=self.account,
                    group_name=group_name,
                    date_partition=self.partition_date,
                    file_name=self.partition_date
                    )

        query = BaseETL.get_query_from_file_name(
            '{query_base_dir}/{query_path}/{file_name}'.format(
                query_base_dir=DATALAKE_QUERIES_DIR,
                query_path=self.raw_query_path,
                file_name=sql_file_name))

        self.athena_client.add_partition(
            database=self.database,
            table_name=table_name,
            partition="dt='{dt}', acc='{acc}'".format(dt=self.partition_date, acc=self.account)
        )

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(date=self.partition_date, account=self.account, group_name=group_name),
            raw_columns=r_cols,
            clean_columns=c_cols
        )

        self.athena_client.add_partition(
            database='datalake_clean',
            table_name=table_name,
            partition="dt_created='{dt}', acc='{acc}', group_name='{group_name}'".format(dt=self.partition_date,
                                                                                         acc=self.account,
                                                                                         group_name=group_name)
        )

    @logger
    def load_to_staging(self, dw_table_name):
        query = self._load_table(dw_table_name)

        query = query.format(date=self.partition_date, account='default')
        logger.info("m=load_to_staging, query={}".format(query))
        self._load_to_staging(dw_table_name, query)

    @logger
    def _load_table(self, table_name):
        table_type = table_name.split('_')[0]
        return getattr(self, '_load_{}_to_staging'.format(table_type))(
            table_name)

    @logger
    def _load_dim_to_staging(self, table_name):
        dim_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR,
                'lifull_campaigns',
                table_name))

        return dim_query

    @logger
    def _load_fact_to_staging(self, table_name):
        int_date = int(self.execution_date.strftime("%Y%m%d"))

        fact_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR,
                'lifull_campaigns',
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

    @logger
    def load_to_prod(self, table_name):
        self._load_to_prod(table_name)
