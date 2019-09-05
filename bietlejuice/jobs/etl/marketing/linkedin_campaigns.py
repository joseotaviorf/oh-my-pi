import os
import re
from collections import OrderedDict

import pandas as pd
import petl
from qa_python_utils.default_logger import QuintoAndarLogger
from qa_python_utils.google.drive import Drive as GoogleDriveClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.marketing import Marketing

logger = QuintoAndarLogger('LinkedInCampaigns')


class LinkedInCampaigns(Marketing):
    INTEGRATION = 'linkedin_campaigns'
    S3_DATA_LAKE_RAW_LINKEDIN_PATH = 'raw/marketing/{}/campaigns'.format(INTEGRATION)
    CAMPAIGN_TABLE_NAME = 'linkedin_campaigns'
    CSV_HEADER = ['Start Date (in UTC)', 'Account Name', 'Currency',
                  'Salesforce Opportunity ID', 'Salesforce Opportunity Line Item ID',
                  'Account Total Budget', 'Account Total Budget End Date (in UTC)',
                  'Campaign ID', 'Campaign Name', 'Campaign Type', 'Campaign Status',
                  'Cost Type', 'Daily Budget', 'Creative Name', 'Ad ID',
                  'Creative Status', 'Ad Introduction Text', 'Ad Headline', 'Ad Line',
                  'Click URL', 'Sponsored Update Type', 'DSC Name', 'Total Spent',
                  'Impressions', 'Clicks', 'Click Through Rate', 'Average CPM',
                  'Average CPC', 'Reactions', 'Comments', 'Shares', 'Follows',
                  'Other Clicks', 'Total Social Actions', 'Total Engagements',
                  'Engagement Rate', 'Viral Impressions', 'Viral Clicks',
                  'Viral Reactions', 'Viral Comments', 'Viral Shares', 'Viral Follows',
                  'Viral Other Clicks', 'Conversions', 'Post-Click Conversions',
                  'View-Through Conversions', 'Conversion Rate', 'Cost per Conversion',
                  'Total Conversion Value', 'Return on Ad Spend', 'Viral Conversions',
                  'Viral Post-Click Conversions', 'Viral View-Through Conversions',
                  'Leads', 'Lead Forms Opened', 'Lead Form Completion Rate',
                  'Cost per Lead', 'Video Length (in Seconds)', 'Video Plays',
                  'Video Views', 'Video View Rate', 'Video Views at 25%',
                  'Video Views at 50%', 'Video Views at 75%', 'Video Completions',
                  'Video Completion Rate', 'Full Screen Plays', 'eCPV',
                  'Viral Video Plays', 'Viral Video Views', 'Viral Video Views at 25%',
                  'Viral Video Views at 50%', 'Viral Video Views at 75%',
                  'Viral Video Completions', 'Viral Video Completion Rate',
                  'Viral Video Full Screen Plays']

    def __init__(self, s3_bucket, execution_date, auth, account=None,
                 extra_configs=None):
        super(LinkedInCampaigns, self).__init__(s3_bucket, execution_date,
                                                self.INTEGRATION, account)
        self.extra_configs = extra_configs

    @logger
    def _get_google_drive_folder_id(self):
        if self.extra_configs and 'gdrive_dir_id' in self.extra_configs and \
                self.extra_configs['gdrive_dir_id'] is not None:
            return self.extra_configs['gdrive_dir_id']

        raise RuntimeError(
            'm=_get_google_drive_folder_id, extra_configs={} msg=Google Drive LinkedIn '
            'Costs folder id not found.'.format(self.extra_configs))

    @logger(exclude='google_drive_client')
    def _get_process_file(self, google_drive_client):
        gdrive_folder_id = self._get_google_drive_folder_id()
        filename = '{}.csv'.format(self.execution_date.strftime('%Y-%m-%d'))
        query = "'{}' in parents and mimeType != 'application/vnd.google-apps.folder'" \
                " and name = '{}'".format(gdrive_folder_id, filename)

        logger.info(
            'm=_get_process_file, filename={}, folder_id={}, msg=Fetching file'.format(
                filename, gdrive_folder_id))

        files = google_drive_client.list_files(None, query)
        self._validate_result(files)

        logger.info(
            'm=move_linkedin_campaigns_to_raw, process_file={}, msg=Downloading file to'
            ' temporary local dir.'.format(files[0]))

        tmp_file = google_drive_client.download_file(file_id=files[0]['id'],
                                                     path='/tmp')
        self._validate_csv_header('/tmp/{}'.format(tmp_file))

        data = pd.read_csv('/tmp/' + tmp_file, sep='\t', skiprows=5,
                           encoding="UTF-16LE", quotechar='"')
        data.drop(columns=['Ad Introduction Text', 'Ad Headline'], inplace=True)

        raw_file = 'raw-{}'.format(tmp_file)
        data.to_csv('/tmp/{}'.format(raw_file), sep='\t', header='true', index=False)

        return raw_file

    @logger
    def _get_header_list(self, file_name):
        header_list = []

        if not os.path.exists(file_name):
            raise RuntimeError('m=_get_header_list, file_name={}, msg=No file found on'
                               ' (Data_Performance)-LinkedInCosts'.format(file_name))

        with open(file_name) as f:
            line = 0
            while line < 6:
                line += 1
                str_header = next(f)

            header_list = str_header.split('\t')
            header_list = [re.sub('\x00|\n', '', a) for a in header_list]

        return header_list

    @logger
    def _validate_csv_header(self, tmp_file):
        header_list = self._get_header_list(tmp_file)

        i = 0
        has_invalid_column = False
        for column in header_list:
            col = column.replace('\n', '')
            if col != self.CSV_HEADER[i]:
                logger.error(
                    'm=_validate_csv_header, column={}, msg=Invalid column'.format(col))
                has_invalid_column = True
                break
            i += 1

        if has_invalid_column or len(header_list) != len(self.CSV_HEADER):
            raise RuntimeError(
                'm=_validate_csv_header, column={}, expected_columns={}, '
                'msg=Columns are not equal expected_columns'.format(self.CSV_HEADER,
                                                                    tmp_file))
        return True

    @logger(exclude='result')
    def _validate_result(self, result):
        if len(result) > 1:
            raise RuntimeError(
                'm=_validate_result, len(result)={}, msg=More than one entity found. '
                'I don\'t know which of them to read!'.format(len(result)))
        elif len(result) == 0:
            raise RuntimeError(
                'm=_validate_result, msg=No entity found in directory')

        return True

    @logger
    def move_linkedin_campaigns_to_raw(self):
        google_drive_client = GoogleDriveClient()
        tmp_file = self._get_process_file(google_drive_client)

        self._save_file_to_s3(tmp_file)

    @logger
    def move_linkedin_campaigns_to_clean(self):
        raw_table_query_file = 'campaigns.sql'
        raw_query_cols = OrderedDict([
            ('account_name', str),
            ('id_campaign', str),
            ('campaign_name', str),
            ('id_ad', str),
            ('ad_name', str),
            ('currency', str),
            ('daily_budget', str),
            ('account_total_budget', str),
            ('total_spent', str),
            ('impressions', str),
            ('clicks', str),
            ('other_clicks', str),
            ('total_engagements', str),
            ('conversions', str),
            ('cost_per_conversion', str),
            ('cost_per_lead', str)
        ])

        self._move_to_clean(
            table_name='marketing_' + self.CAMPAIGN_TABLE_NAME,
            sql_file_name=raw_table_query_file,
            r_cols=raw_query_cols,
            c_cols=raw_query_cols
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean(self, table_name, sql_file_name, r_cols, c_cols=None):
        key = 'clean/marketing/{integration}/{table_name}/' \
              'dt_created={date_partition}/{file_name}.parquet' \
            .format(integration=self.integration, table_name=table_name,
                    date_partition=self.partition_date, file_name=self.partition_date)

        query = BaseETL.get_query_from_file_name(
            '{query_base_dir}/{query_path}/{file_name}'.format(
                query_base_dir=DATALAKE_QUERIES_DIR,
                query_path=self.raw_query_path,
                file_name=sql_file_name))

        self.athena_client.add_partition(
            database=self.database,
            table_name=table_name,
            partition="dt='{dt}'".format(dt=self.partition_date)
        )

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.format(date=self.partition_date),
            raw_columns=r_cols,
            clean_columns=c_cols
        )

        self.athena_client.add_partition(
            database='datalake_clean',
            table_name=table_name,
            partition="dt_created='{dt}'".format(dt=self.partition_date)
        )

    @logger
    def _save_file_to_s3(self, tmp_filename):
        bucket_folder_path = '{}/{}/dt={}'.format(
            self.s3_bucket,
            self.S3_DATA_LAKE_RAW_LINKEDIN_PATH,
            self.execution_date.strftime('%Y-%m-%d'))

        logger.info(
            'm=_save_file_to_s3, tmp_file={}, s3_path={}, msg=Uploading tmp '
            'file to S3.'.format(tmp_filename, bucket_folder_path))

        BaseETL.file_to_s3(filename=tmp_filename, bucket_folder_path=bucket_folder_path)

        logger.info('m=_save_file_to_s3, msg=Successfully uploaded file')

        self.athena_client.add_partition(
            database='datalake_raw',
            table_name='marketing_' + self.CAMPAIGN_TABLE_NAME,
            partition="dt='{dt}'".format(dt=self.partition_date)
        )

    @logger
    def load_to_staging(self, dw_table_name):
        query = self._get_staging_table_query(dw_table_name)
        query = query.format(date=self.partition_date)
        logger.info("m=load_to_staging, query={}".format(query))

        self._load_to_staging(dw_table_name, query)

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
            append=False if self._table_type(dw_table_name) == 'dim' else True,
            commit=True
        )

    @staticmethod
    @logger
    def _table_type(table_name):
        return table_name.split('_')[0]

    @logger
    def _delete_staging_fact_rows(self, table_name, sk_date):
        delete_query = "DELETE FROM staging.{table_name} " \
                       "WHERE sk_date = {date}".format(table_name=table_name,
                                                       date=sk_date)
        logger.info("m=_delete_staging_fact_rows, query={}".format(delete_query))

        BaseETL.execute_command(
            db_enum=EnumDB.BI_DW,
            command=delete_query,
            commit=True,
            encoding='utf-8'
        )

    @logger
    def _get_staging_table_query(self, table_name):
        full_load_query = BaseETL.get_query_from_file_name(
            '{}/marketing/{}/clean_to_staging/{}.sql'.format(
                DATALAKE_QUERIES_DIR, self.INTEGRATION, table_name))

        if self._table_type(table_name) == 'fact' and not self._is_staging_table_empty(
                table_name):
            sk_date = int(self.execution_date.strftime('%Y%m%d'))
            self._delete_staging_fact_rows(table_name, sk_date)

            daily_load_query = "{} \nWHERE sk_date = {};".format(full_load_query,
                                                                 sk_date)
            return daily_load_query

        return full_load_query

    @logger
    def load_to_prod(self, table_name):
        self._load_to_prod(table_name)
