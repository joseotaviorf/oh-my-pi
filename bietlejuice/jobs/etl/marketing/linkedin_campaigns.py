import json
from collections import OrderedDict
from gzip import GzipFile
from io import BytesIO

import petl
from qa_python_utils.default_logger import QuintoAndarLogger
from quintoandar_linkedin_client.constants import ENTITIES, ENTITIES_URN_PREFIX, \
    ENTITIES_SEARCH_KEYS
from quintoandar_linkedin_client.linkedin_client import LinkedInClient
from quintoandar_linkedin_client.request import Request

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.marketing import Marketing

logger = QuintoAndarLogger('LinkedInCampaigns')


class LinkedInCampaigns(Marketing):
    INTEGRATION = 'linkedin_ads'
    S3_DATA_LAKE_RAW_LINKEDIN_PATH = 'raw/marketing/{}'.format(INTEGRATION)
    S3_CAM_GROUPS_FOLDER = 'campaign_groups'
    S3_CAMPAIGNS_FOLDER = 'campaigns'
    S3_CREATIVES_FOLDER = 'creatives'
    S3_CREATIVES_STATS_FOLDER = 'creatives_stats'
    CAMPAIGN_GROUPS_TABLE_NAME = 'linkedin_campaign_groups'
    CAMPAIGNS_TABLE_NAME = 'linkedin_campaigns'
    CREATIVES_TABLE_NAME = 'linkedin_creatives'
    CREATIVES_STATS_TABLE_NAME = 'linkedin_creatives_stats'

    def __init__(self, s3_bucket, execution_date, auth, account=None,
                 extra_configs=None):
        super(LinkedInCampaigns, self).__init__(s3_bucket, execution_date,
                                                self.INTEGRATION, account)
        self.extra_configs = extra_configs
        self.auth = auth
        self._sdk_client = None

    @property
    def client(self):
        if self._sdk_client is not None:
            return self._sdk_client

        self._sdk_client = LinkedInClient(self.auth['API_KEY'], self.auth['API_SECRET'],
                                          refresh_token=self.auth['REFRESH_TOKEN'])
        return self._sdk_client

    @staticmethod
    def _split_into_chunks(raw_list, chunk_size):
        for i in range(0, len(raw_list), chunk_size):
            yield raw_list[i:i + chunk_size]

    @staticmethod
    def __get_ids(dict_list):
        return [d['id'] for d in dict_list]

    @logger
    def get_accounts(self):
        accounts_cursor = self.client.get_accounts()
        logger.info(
            'm=_get_accounts, msg=Found {} accounts.'.format(accounts_cursor.count))

        return [] if accounts_cursor.count == 0 else accounts_cursor

    @logger
    def _get_campaign_groups(self, acc):
        p = Request.build_args(ENTITIES_SEARCH_KEYS.ACCOUNT,
                               ENTITIES_URN_PREFIX.ACCOUNT,
                               [acc.id])

        cg_list = []
        for cg in self.client.get_campaign_groups(params=p):
            cg_dict = {
                'id': cg.id,
                'name': cg.name,
                'backfilled': cg.backfilled,
                'run_schedule_start': cg.run_schedule_start,
                'run_schedule_end': cg.run_schedule_end,
                'serving_statuses': cg.serving_statuses,
                'status': cg.status,
                'total_budget_amount': cg.total_budget_amount,
                'total_budget_currency_code': cg.total_budget_currency_code,
                'account_id': acc.id,
                'account_name': acc.name
            }
            cg_list.append(cg_dict)

        logger.info('m=_get_campaign_groups, msg=Found {} campaign groups.'.
                    format(len(cg_list)))
        return cg_list

    @logger(exclude='cg_id_ls')
    def _get_campaigns(self, cg_id_ls):
        p = Request.build_args(ENTITIES_SEARCH_KEYS.CAMPAIGN_GROUP,
                               ENTITIES_URN_PREFIX.CAMPAIGN_GROUP, cg_id_ls)

        cam_list = []
        for cam in self.client.get_campaigns(params=p):
            cg_dict = {
                'id': cam.id,
                'name': cam.name,
                'associated_entity': cam.associated_entity,
                'audience_expansion_enabled': cam.audience_expansion_enabled,
                'campaign_group_id': cam.campaign_group[len(ENTITIES_URN_PREFIX.
                                                            CAMPAIGN_GROUP):],
                'cost_type': cam.cost_type,
                'creative_selection': cam.creative_selection,
                'daily_budget_amount': cam.daily_budget_amount,
                'daily_budget_currencyCode': cam.daily_budget_currencyCode,
                'locale_country': cam.locale_country,
                'locale_language': cam.locale_language,
                'objective_type': cam.objective_type,
                'offsite_preferences': cam.offsite_preferences,
                'run_schedule_start': cam.run_schedule_start,
                'run_schedule_end': cam.run_schedule_end,
                'targeting_excluded_targeting_facets':
                    cam.targeting_excluded_targeting_facets,
                'targeting_included_targeting_facets':
                    cam.targeting_included_targeting_facets,
                'targeting_criteria': cam.targeting_criteria,
                'total_budget_amount': cam.total_budget_amount,
                'total_budget_currencyCode': cam.total_budget_currencyCode,
                'type': cam.type,
                'unit_cost_amount': cam.unit_cost_amount,
                'unit_cost_currency_code': cam.unit_cost_currency_code,
                'version_tag': cam.version_tag,
                'status': cam.status,
                'optimizationTargetType': cam.optimizationTargetType,
                'format': cam.format,
                'account_id': cam.account[len(ENTITIES_URN_PREFIX.ACCOUNT):]
            }
            cam_list.append(cg_dict)

        logger.info('m=_get_campaigns, msg=Found {} campaigns.'.format(len(cam_list)))
        return cam_list

    @logger(exclude='campaigns_ids')
    def _get_creatives(self, campaigns_ids):
        p_cam_ids = Request.build_args(ENTITIES_SEARCH_KEYS.CAMPAIGN,
                                       ENTITIES_URN_PREFIX.CAMPAIGN,
                                       campaigns_ids)

        creative_list = []
        for cr in self.client.get_creatives(params=p_cam_ids):
            cr_dict = {
                'id': cr.id,
                'campaign': cr.campaign,
                'processing_state': cr.processing_state,
                'reference': cr.reference,
                'review': cr.review,
                'serving_statuses': cr.serving_statuses,
                'status': cr.status,
                'type': cr.type,
                'variables': cr.variables
            }
            creative_list.append(cr_dict)

        logger.info(
            'm=_get_creatives, msg=Found {} creatives.'.format(len(creative_list)))
        return creative_list

    @logger(exclude=['creative_ids'])
    def _get_creatives_stats(self, creative_ids):
        today = self.execution_date.date()

        # The API returns a max of 100 elements by request, so it makes more sense
        # making a call by each batch part
        batch_ids = self._split_into_chunks(creative_ids, 100)
        ads_stats_ls = []
        for _ids in batch_ids:
            stats_cursor = self.client.ads_analytics(entity=ENTITIES.CREATIVES,
                                                     creative_ids=_ids,
                                                     start_date=today,
                                                     end_date=today)
            for stat in stats_cursor:
                stat_dict = {
                    'card_clicks': stat.card_clicks,
                    'card_impressions': stat.card_impressions,
                    'clicks': stat.clicks,
                    'comments': stat.comments,
                    'company_page_clicks': stat.company_page_clicks,
                    'cost_in_local_currency': stat.cost_in_local_currency,
                    'follows': stat.follows,
                    'impressions': stat.impressions,
                    'likes': stat.likes,
                    'opens': stat.opens,
                    'pivot_value': stat.pivot_value,
                    'reactions': stat.reactions,
                    'sends': stat.sends,
                    'shares': stat.shares,
                    'text_url_clicks': stat.text_url_clicks,
                }
                ads_stats_ls.append(stat_dict)

        logger.info(
            'm=_get_creatives_stats, msg=Found {} creative stats.'.format(
                len(ads_stats_ls)))
        return ads_stats_ls

    @logger
    def _fetch_and_save_campaign_groups(self, acc):
        cam_groups = self._get_campaign_groups(acc)
        self._save_to_s3(acc.id, self.S3_CAM_GROUPS_FOLDER, cam_groups)

        return self.__get_ids(cam_groups)

    @logger(exclude=['cam_group_ids'])
    def _fetch_and_save_campaigns(self, acc, cam_group_ids):
        campaigns = self._get_campaigns(cam_group_ids)
        self._save_to_s3(acc.id, self.S3_CAMPAIGNS_FOLDER, campaigns)

        return self.__get_ids(campaigns)

    @logger(exclude=['campaigns_ids'])
    def _fetch_and_save_creatives(self, acc, campaigns_ids):
        creatives = self._get_creatives(campaigns_ids)
        self._save_to_s3(acc.id, self.S3_CREATIVES_FOLDER, creatives)

        return self.__get_ids(creatives)

    @logger(exclude=['creative_ids'])
    def _fetch_and_save_creatives_stats(self, acc, creative_ids):
        creatives = self._get_creatives_stats(creative_ids)
        self._save_to_s3(acc.id, self.S3_CREATIVES_STATS_FOLDER, creatives)

    @logger
    def move_linkedin_campaigns_to_raw(self):
        accs_cursor = self.get_accounts()
        if not accs_cursor:
            raise RuntimeError(
                'm=move_linkedin_campaigns_to_raw, msg=No accounts where found!')

        for acc in accs_cursor:
            cam_group_ids = self._fetch_and_save_campaign_groups(acc)
            if cam_group_ids:
                campaigns_ids = self._fetch_and_save_campaigns(acc, cam_group_ids)

                if campaigns_ids:
                    creatives_ids = self._fetch_and_save_creatives(acc, campaigns_ids)

                    if creatives_ids:
                        self._fetch_and_save_creatives_stats(acc, creatives_ids)

    @logger
    def move_linkedin_campaign_groups_to_clean(self):
        raw_table_query_file = 'campaign_groups.sql'
        raw_query_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('status', str),
            ('total_cost', str),
            ('total_cost_currency_code', str),
            ('run_schedule_start', str),
            ('run_schedule_end', str),
            ('backfilled', str),
            ('id_account', str),
            ('account_name', str)
        ])

        self._move_to_clean(
            table_name='marketing_{}'.format(self.CAMPAIGN_GROUPS_TABLE_NAME),
            sql_file_name=raw_table_query_file,
            r_cols=raw_query_cols,
            c_cols=raw_query_cols
        )

    @logger
    def move_linkedin_campaigns_to_clean(self):
        raw_table_query_file = 'campaigns.sql'
        raw_query_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('id_campaign_group', str),
            ('id_account', str),
            ('cost_type', str),
            ('daily_cost', str),
            ('daily_currency_code', str),
            ('total_cost', str),
            ('total_cost_currency_code', str),
            ('unit_cost', str),
            ('unit_cost_currency_code', str),
            ('objective_type', str),
            ('run_schedule_start', str),
            ('run_schedule_end', str),
            ('type', str),
            ('status', str),
            ('locale_country', str),
            ('locale_language', str)
        ])

        self._move_to_clean(
            table_name='marketing_{}'.format(self.CAMPAIGNS_TABLE_NAME),
            sql_file_name=raw_table_query_file,
            r_cols=raw_query_cols,
            c_cols=raw_query_cols
        )

    @logger
    def move_linkedin_creatives_to_clean(self):
        raw_table_query_file = 'creatives.sql'
        raw_query_cols = OrderedDict([
            ('id', str),
            ('id_campaign', str),
            ('status', str),
            ('type', str)
        ])

        self._move_to_clean(
            table_name='marketing_{}'.format(self.CREATIVES_TABLE_NAME),
            sql_file_name=raw_table_query_file,
            r_cols=raw_query_cols,
            c_cols=raw_query_cols
        )

    @logger
    def move_linkedin_creatives_stats_to_clean(self):
        raw_table_query_file = 'creatives_stats.sql'
        raw_query_cols = OrderedDict([
            ('id_creative', str),
            ('card_clicks', str),
            ('card_impressions', str),
            ('clicks', str),
            ('comments', str),
            ('company_page_clicks', str),
            ('cost_in_local_currency', str),
            ('follows', str),
            ('impressions', str),
            ('likes', str),
            ('opens', str),
            ('reactions', str),
            ('sends', str),
            ('shares', str),
            ('text_url_clicks', str),
        ])

        self._move_to_clean(
            table_name='marketing_{}'.format(self.CREATIVES_STATS_TABLE_NAME),
            sql_file_name=raw_table_query_file,
            r_cols=raw_query_cols,
            c_cols=raw_query_cols
        )

    @logger(exclude='raw_data')
    def _save_to_s3(self, id_account, entity_name, raw_data):
        """
            This method saves the json on the data lake raw as a compacted gzip file
            Every row is broken in lines, so that Athena will compute
        """

        if len(raw_data) == 0:
            logger.info('m=_save_to_s3, msg=There\'s no data to be saved.')
            return

        gz_body = BytesIO()
        for _dict in raw_data:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_dict, ensure_ascii=False)).encode('utf-8'))
                fp.write('\n')

        s3_file_path = '{}/{}/acc={}/dt={}/data.gz'.format(
            self.S3_DATA_LAKE_RAW_LINKEDIN_PATH,
            entity_name,
            id_account,
            self.execution_date.strftime('%Y-%m-%d'))

        logger.info(
            'm=_save_to_s3, dest={}, msg=Saving LinkedIn {} data into s3 bucket'.format(
                s3_file_path, entity_name))

        BaseETL.obj_to_s3(
            obj_io=gz_body,
            bucket=self.s3_bucket,
            file_path=s3_file_path
        )

        # always flush after using!
        gz_body.seek(0)
        gz_body.flush()

        logger.info('m=_save_to_s3, msg=Saved with success!')

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
