from collections import OrderedDict
from datetime import datetime

import mock
import petl
from mock import MagicMock, Mock
from pytest import raises
from quintoandar_linkedin_client.constants import ENTITIES_URN_PREFIX
from quintoandar_linkedin_client.linkedin_client import LinkedInClient
from quintoandar_linkedin_client.request import Request

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl.marketing.linkedin_campaigns import LinkedInCampaigns


class TestLinkedInCampaigns(object):

    @mock.patch('bietlejuice.jobs.etl.marketing.linkedin_campaigns.LinkedInClient')
    def test_client(self, linkedin_client, linkedin_campaigns):
        # arrange
        mk_cli = Mock()
        linkedin_client.return_value = mk_cli
        # act
        exp_cli = linkedin_campaigns.client
        exp_cli_cached = linkedin_campaigns.client

        # assert
        assert exp_cli == mk_cli
        assert exp_cli == exp_cli_cached

    @mock.patch.object(LinkedInClient, 'get_accounts')
    def test_get_accounts(self, mock_get_accounts, linkedin_campaigns):
        # arrange
        mock_return = [{}]
        mock_get_accounts.return_value = mock_return

        # act
        acc_cursor = linkedin_campaigns.get_accounts()

        # assert
        assert mock_return == acc_cursor

    @mock.patch.object(LinkedInClient, 'get_campaign_groups')
    @mock.patch.object(Request, 'build_args')
    def test_get_campaign_groups(self, mock_build_args, mock_get_campaign_groups,
                                 linkedin_campaigns):
        # arrange
        mk_cam = Mock()
        mock_return = [mk_cam]
        mock_get_campaign_groups.return_value = mock_return
        mk_acc = Mock()

        # act
        cg_list = linkedin_campaigns._get_campaign_groups(mk_acc)

        # assert
        assert [{
            'id': mk_cam.id,
            'name': mk_cam.name,
            'backfilled': mk_cam.backfilled,
            'run_schedule_start': mk_cam.run_schedule_start,
            'run_schedule_end': mk_cam.run_schedule_end,
            'serving_statuses': mk_cam.serving_statuses,
            'status': mk_cam.status,
            'total_budget_amount': mk_cam.total_budget_amount,
            'total_budget_currency_code': mk_cam.total_budget_currency_code,
            'account_id': mk_acc.id,
            'account_name': mk_acc.name
        }] == cg_list

    @mock.patch.object(LinkedInClient, 'get_campaigns')
    @mock.patch.object(Request, 'build_args')
    def test_get_campaigns(self, mock_build_args, mock_get_campaigns,
                           linkedin_campaigns):
        # arrange
        mk_cam = Mock()
        mk_cam.campaign_group = ''
        mk_cam.account = ''
        mock_return = [mk_cam]
        mock_get_campaigns.return_value = mock_return

        # act
        cam_list = linkedin_campaigns._get_campaigns(Mock())

        # assert
        assert [{
            'id': mk_cam.id,
            'name': mk_cam.name,
            'associated_entity': mk_cam.associated_entity,
            'audience_expansion_enabled': mk_cam.audience_expansion_enabled,
            'campaign_group_id': mk_cam.campaign_group[len(ENTITIES_URN_PREFIX.
                                                           CAMPAIGN_GROUP):],
            'cost_type': mk_cam.cost_type,
            'creative_selection': mk_cam.creative_selection,
            'daily_budget_amount': mk_cam.daily_budget_amount,
            'daily_budget_currencyCode': mk_cam.daily_budget_currencyCode,
            'locale_country': mk_cam.locale_country,
            'locale_language': mk_cam.locale_language,
            'objective_type': mk_cam.objective_type,
            'offsite_preferences': mk_cam.offsite_preferences,
            'run_schedule_start': mk_cam.run_schedule_start,
            'run_schedule_end': mk_cam.run_schedule_end,
            'targeting_excluded_targeting_facets':
                mk_cam.targeting_excluded_targeting_facets,
            'targeting_included_targeting_facets':
                mk_cam.targeting_included_targeting_facets,
            'targeting_criteria': mk_cam.targeting_criteria,
            'total_budget_amount': mk_cam.total_budget_amount,
            'total_budget_currencyCode': mk_cam.total_budget_currencyCode,
            'type': mk_cam.type,
            'unit_cost_amount': mk_cam.unit_cost_amount,
            'unit_cost_currency_code': mk_cam.unit_cost_currency_code,
            'version_tag': mk_cam.version_tag,
            'status': mk_cam.status,
            'optimizationTargetType': mk_cam.optimizationTargetType,
            'format': mk_cam.format,
            'account_id': mk_cam.account[len(ENTITIES_URN_PREFIX.ACCOUNT):]
        }] == cam_list

    @mock.patch.object(LinkedInClient, 'get_creatives')
    @mock.patch.object(Request, 'build_args')
    def test_get_creatives(self, mock_build_args, mock_get_creatives,
                           linkedin_campaigns):
        # arrange
        mk_crs = Mock()
        mk_crs.campaign_group = ''
        mk_crs.account = ''
        mock_return = [mk_crs]
        mock_get_creatives.return_value = mock_return

        # act
        cr_list = linkedin_campaigns._get_creatives(Mock())

        # assert
        assert [{
            'id': mk_crs.id,
            'campaign': mk_crs.campaign,
            'processing_state': mk_crs.processing_state,
            'reference': mk_crs.reference,
            'review': mk_crs.review,
            'serving_statuses': mk_crs.serving_statuses,
            'status': mk_crs.status,
            'type': mk_crs.type,
            'variables': mk_crs.variables
        }] == cr_list

    @mock.patch.object(LinkedInClient, 'ads_analytics')
    def test_get_crv_stats(self, mock_ads_analytics, linkedin_campaigns):
        # arrange
        mk_cr_stats = Mock()
        mk_cr_stats.campaign_group = ''
        mk_cr_stats.account = ''
        mock_stats_cursor = [mk_cr_stats]
        mock_ads_analytics.return_value = mock_stats_cursor

        # act
        cr_stats_list = linkedin_campaigns._get_creatives_stats(range(0, 100))

        # assert
        assert [{
            'external_website_post_click_conversions': mk_cr_stats.external_website_post_click_conversions,
            'ad_unit_clicks': mk_cr_stats.ad_unit_clicks,
            'company_page_clicks': mk_cr_stats.company_page_clicks,
            'viral_one_click_leads': mk_cr_stats.viral_one_click_leads,
            'text_url_clicks': mk_cr_stats.text_url_clicks,
            'viral_comment_likes': mk_cr_stats.viral_comment_likes,
            'viral_external_website_conversions': mk_cr_stats.viral_external_website_conversions,
            'pivot': mk_cr_stats.pivot,
            'card_clicks': mk_cr_stats.card_clicks,
            'likes': mk_cr_stats.likes,
            'viral_comments': mk_cr_stats.viral_comments,
            'one_click_leads': mk_cr_stats.one_click_leads,
            'viral_card_impressions': mk_cr_stats.viral_card_impressions,
            'follows': mk_cr_stats.follows,
            'viral_one_click_lead_form_opens': mk_cr_stats.viral_one_click_lead_form_opens,
            'conversion_value_in_local_currency': mk_cr_stats.conversion_value_in_local_currency,
            'viral_follows': mk_cr_stats.viral_follows,
            'other_engagements': mk_cr_stats.other_engagements,
            'card_impressions': mk_cr_stats.card_impressions,
            'lead_generation_mail_interested_clicks': mk_cr_stats.lead_generation_mail_interested_clicks,
            'opens': mk_cr_stats.opens,
            'total_engagements': mk_cr_stats.total_engagements,
            'viral_reactions': mk_cr_stats.viral_reactions,
            'viral_impressions': mk_cr_stats.viral_impressions,
            'date_range': mk_cr_stats.date_range,
            'cost_in_local_currency': mk_cr_stats.cost_in_local_currency,
            'viral_likes': mk_cr_stats.viral_likes,
            'viral_other_engagements': mk_cr_stats.viral_other_engagements,
            'shares': mk_cr_stats.shares,
            'viral_card_clicks': mk_cr_stats.viral_card_clicks,
            'viral_external_website_post_view_conversions': mk_cr_stats.viral_external_website_post_view_conversions,
            'viral_total_engagements': mk_cr_stats.viral_total_engagements,
            'viral_company_page_clicks': mk_cr_stats.viral_company_page_clicks,
            'action_clicks': mk_cr_stats.action_clicks,
            'viral_shares': mk_cr_stats.viral_shares,
            'pivot_value': mk_cr_stats.pivot_value,
            'comments': mk_cr_stats.comments,
            'external_website_post_view_conversions': mk_cr_stats.external_website_post_view_conversions,
            'cost_in_usd': mk_cr_stats.cost_in_usd,
            'landing_page_clicks': mk_cr_stats.landing_page_clicks,
            'one_click_lead_form_opens': mk_cr_stats.one_click_lead_form_opens,
            'impressions': mk_cr_stats.impressions,
            'sends': mk_cr_stats.sends,
            'viral_landing_page_clicks': mk_cr_stats.viral_landing_page_clicks,
            'viral_external_website_post_click_conversions': mk_cr_stats.viral_external_website_post_click_conversions,
            'external_website_conversions': mk_cr_stats.external_website_conversions,
            'lead_generation_mail_contact_info_shares': mk_cr_stats.lead_generation_mail_contact_info_shares,
            'clicks': mk_cr_stats.clicks,
            'reactions': mk_cr_stats.reactions,
            'viral_clicks': mk_cr_stats.viral_clicks,
            'pivot_values': mk_cr_stats.pivot_values,
        }] == cr_stats_list

    @mock.patch.object(LinkedInCampaigns, '_get_campaign_groups')
    @mock.patch.object(LinkedInCampaigns, '_save_to_s3')
    def test_fetch_and_save_campaign_groups(self, mock_save_to_s3, mock_get_camp_groups,
                                            linkedin_campaigns):
        # arrange
        mk_ids = [{'id': 1}, {'id': 3}]
        mock_get_camp_groups.return_value = mk_ids
        mk_acc = Mock()

        # act
        cg_ids = linkedin_campaigns._fetch_and_save_campaign_groups(mk_acc)

        # assert
        assert mk_ids[0]['id'] == cg_ids[0]
        assert mk_ids[1]['id'] == cg_ids[1]
        mock_get_camp_groups.assert_called_once_with(mk_acc)
        mock_save_to_s3.assert_called_once_with(mk_acc.id,
                                                linkedin_campaigns.S3_CAM_GROUPS_FOLDER,
                                                mk_ids)

    @mock.patch.object(LinkedInCampaigns, '_get_campaigns')
    @mock.patch.object(LinkedInCampaigns, '_save_to_s3')
    def test_fetch_and_save_campaigns(self, mock_save_to_s3, mock_get_camp,
                                      linkedin_campaigns):
        # arrange
        mk_ids = [{'id': 1}, {'id': 3}]
        mock_get_camp.return_value = mk_ids
        mk_acc = Mock()

        # act
        cg_ids = linkedin_campaigns._fetch_and_save_campaigns(mk_acc, mock.ANY)

        # assert
        assert mk_ids[0]['id'] == cg_ids[0]
        assert mk_ids[1]['id'] == cg_ids[1]
        mock_get_camp.assert_called_once_with(mk_acc)
        mock_save_to_s3.assert_called_once_with(mk_acc.id,
                                                linkedin_campaigns.S3_CAMPAIGNS_FOLDER,
                                                mk_ids)

    @mock.patch.object(LinkedInCampaigns, '_get_creatives')
    @mock.patch.object(LinkedInCampaigns, '_save_to_s3')
    def test_fetch_and_save_creatives(self, mock_save_to_s3, mock_get_creatives,
                                      linkedin_campaigns):
        # arrange
        mk_ids = [{'id': 1}, {'id': 3}]
        mock_get_creatives.return_value = mk_ids
        mk_acc = Mock()
        cr_ids = mock.ANY

        # act
        cg_ids = linkedin_campaigns._fetch_and_save_creatives(mk_acc, cr_ids)

        # assert
        assert mk_ids[0]['id'] == cg_ids[0]
        assert mk_ids[1]['id'] == cg_ids[1]
        mock_get_creatives.assert_called_once_with(cr_ids)
        mock_save_to_s3.assert_called_once_with(mk_acc.id,
                                                linkedin_campaigns.S3_CREATIVES_FOLDER,
                                                mk_ids)

    @mock.patch.object(LinkedInCampaigns, '_get_creatives_stats')
    @mock.patch.object(LinkedInCampaigns, '_save_to_s3')
    def test_fetch_and_save_crv_stats(self, mock_save_to_s3, mock_get_creatives,
                                      linkedin_campaigns):
        # arrange
        mk_ids = [{'id': 1}, {'id': 3}]
        mock_get_creatives.return_value = mk_ids
        mk_acc = Mock()

        # act
        cg_ids = linkedin_campaigns._fetch_and_save_creatives_stats(mk_acc, mock.ANY)

        # assert
        mock_get_creatives.assert_called_once_with(cg_ids)
        mock_save_to_s3.assert_called_once_with(
            mk_acc.id, linkedin_campaigns.S3_CREATIVES_STATS_FOLDER, mk_ids)

    @mock.patch.object(LinkedInCampaigns, 'get_accounts')
    def test_move_linkedin_campaigns_to_raw_error(self, mk_accs, linkedin_campaigns):
        # arrange
        mk_accs.return_value = []

        # assert
        with raises(RuntimeError):
            # act
            linkedin_campaigns.move_linkedin_campaigns_to_raw()

    @mock.patch.object(LinkedInCampaigns, '_fetch_and_save_creatives_stats')
    @mock.patch.object(LinkedInCampaigns, '_fetch_and_save_creatives')
    @mock.patch.object(LinkedInCampaigns, '_fetch_and_save_campaigns')
    @mock.patch.object(LinkedInCampaigns, '_fetch_and_save_campaign_groups')
    @mock.patch.object(LinkedInCampaigns, 'get_accounts')
    def test_move_linkedin_campaigns_to_raw(self, mk_accs, mk_cg, mk_cam, mk_crs,
                                            mk_crs_stats, linkedin_campaigns):
        # arrange
        acc = Mock()
        mk_accs.return_value = [acc]

        cgs = [Mock()]
        mk_cg.return_value = cgs

        cams = [Mock()]
        mk_cam.return_value = cams

        cr1 = Mock()
        mk_crs.return_value = [cr1]

        # act
        linkedin_campaigns.move_linkedin_campaigns_to_raw()

        # assert
        mk_accs.assert_called_once_with()
        mk_cg.assert_called_once_with(acc)
        mk_cam.assert_called_once_with(acc, cgs)
        mk_crs.assert_called_once_with(acc, cams)

    @mock.patch.object(BaseETL, 'obj_to_s3')
    def test_save_to_s3_with_empty_data(self, mock_obj_to_s3, linkedin_campaigns):
        # act
        linkedin_campaigns._save_to_s3(mock.ANY, mock.ANY, [])

        # assert
        mock_obj_to_s3.assert_not_called()

    @mock.patch.object(BaseETL, 'obj_to_s3')
    @mock.patch('bietlejuice.jobs.etl.marketing.linkedin_campaigns.BytesIO')
    def test_save_to_s3(self, mock__bytes_io, mock__obj_to_s3, linkedin_campaigns):
        # arrange
        mocked_bytes_io = MagicMock()
        mock__bytes_io.return_value = mocked_bytes_io

        mock_pendulum = Mock()
        mock_pendulum.strftime = MagicMock(return_value='2019-09-22')
        linkedin_campaigns.execution_date = mock_pendulum

        account_id = '1a1b1c'
        entity_name = 'campaigns'
        raw_data = [{'abada': 'badoo'}]
        expected_s3_file_path = '{}/{}/acc={}/dt={}/data.gz'.format(
            linkedin_campaigns.S3_DATA_LAKE_RAW_LINKEDIN_PATH,
            entity_name,
            account_id,
            linkedin_campaigns.execution_date.strftime('%Y-%m-%d'))

        # act
        linkedin_campaigns._save_to_s3(account_id, entity_name, raw_data)

        # assert
        mock__obj_to_s3.assert_called_with(obj_io=mocked_bytes_io,
                                           bucket=linkedin_campaigns.s3_bucket,
                                           file_path=expected_s3_file_path)

    @mock.patch.object(LinkedInCampaigns, '_move_to_clean')
    def test_move_linkedin_campaign_groups_to_clean(self, mock__move_to_clean,
                                                    linkedin_campaigns):
        # act
        linkedin_campaigns.move_linkedin_campaign_groups_to_clean()

        # assert
        raw_table_query_file = 'campaign_groups.sql'
        raw_cols = OrderedDict([
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

        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_linkedin_campaign_groups',
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=raw_cols)

    @mock.patch.object(LinkedInCampaigns, '_move_to_clean')
    def test_move_linkedin_campaigns_to_clean(self, mock__move_to_clean,
                                              linkedin_campaigns):
        # act
        linkedin_campaigns.move_linkedin_campaigns_to_clean()

        # assert
        raw_table_query_file = 'campaigns.sql'
        raw_cols = OrderedDict([
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

        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_linkedin_campaigns',
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=raw_cols)

    @mock.patch.object(LinkedInCampaigns, '_move_to_clean')
    def test_move_linkedin_creatives_to_clean(self, mock__move_to_clean,
                                              linkedin_campaigns):
        # act
        linkedin_campaigns.move_linkedin_creatives_to_clean()

        # assert
        raw_table_query_file = 'creatives.sql'
        raw_cols = OrderedDict([
            ('id', str),
            ('id_campaign', str),
            ('status', str),
            ('type', str)
        ])

        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_linkedin_creatives',
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=raw_cols)

    @mock.patch.object(LinkedInCampaigns, '_move_to_clean')
    def test_move_linkedin_creatives_stats_to_clean(self, mock__move_to_clean,
                                                    linkedin_campaigns):
        # act
        linkedin_campaigns.move_linkedin_creatives_stats_to_clean()

        # assert
        raw_table_query_file = 'creatives_stats.sql'
        raw_cols = OrderedDict([
            ('id_creative', str),
            ('cost_in_local_currency', str),
            ('cost_in_usd', str),
            ('card_clicks', str),
            ('likes', str),
            ('impressions', str),
            ('action_clicks', str),
            ('comments', str),
            ('external_website_post_click_conversions', str),
            ('ad_unit_clicks', str),
            ('company_page_clicks', str),
            ('one_click_leads', str),
            ('text_url_clicks', str),
            ('card_impressions', str),
            ('follows', str),
            ('conversion_value_in_local_currency', str),
            ('other_engagements', str),
            ('lead_generation_mail_interested_clicks', str),
            ('opens', str),
            ('total_engagements', str),
            ('shares', str),
            ('external_website_post_view_conversions', str),
            ('landing_page_clicks', str),
            ('one_click_lead_form_opens', str),
            ('sends', str),
            ('external_website_conversions', str),
            ('lead_generation_mail_contact_info_shares', str),
            ('clicks', str),
            ('reactions', str),
            ('viral_shares', str),
            ('viral_card_impressions', str),
            ('viral_one_click_leads', str),
            ('viral_external_website_conversions', str),
            ('viral_comment_likes', str),
            ('viral_comments', str),
            ('viral_impressions', str),
            ('viral_one_click_lead_form_opens', str),
            ('viral_follows', str),
            ('viral_reactions', str),
            ('viral_likes', str),
            ('viral_other_engagements', str),
            ('viral_card_clicks', str),
            ('viral_external_website_post_view_conversions', str),
            ('viral_total_engagements', str),
            ('viral_company_page_clicks', str),
            ('viral_landing_page_clicks', str),
            ('viral_external_website_post_click_conversions', str),
            ('viral_clicks', str),
        ])

        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_linkedin_creatives_stats',
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=raw_cols)

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test__move_to_clean(self, mock_get_query_from_file_name, linkedin_campaigns):
        # arrange
        table_name = 'cool_table'
        sql_file_name = 'some query'
        r_cols = 'r_cols'
        linkedin_campaigns.athena_client.add_partition = Mock()
        linkedin_campaigns.athena_client.create_parquet_from_query = Mock()

        # act
        linkedin_campaigns._move_to_clean(table_name, sql_file_name, r_cols, r_cols)

        # assert
        mock_get_query_from_file_name.assert_called_once()
        assert linkedin_campaigns.athena_client.add_partition.call_count == 2

    @mock.patch.object(LinkedInCampaigns, '_get_staging_table_query')
    @mock.patch.object(LinkedInCampaigns, '_load_to_staging')
    def test_load_to_staging(self, mock__load_to_staging, mock__get_staging_table_query,
                             linkedin_campaigns):
        # arrange
        dw_table_name = 'dim_table_c'
        query = 'cool_query'
        mock__get_staging_table_query.return_value = query

        # act
        linkedin_campaigns.load_to_staging(dw_table_name)

        # assert
        mock__load_to_staging.assert_called_once_with(dw_table_name, query)

    @mock.patch.object(BaseETL, 'execute_command')
    def test__delete_staging_fact_rows(self, mock_bulk_insert, linkedin_campaigns):
        # act
        linkedin_campaigns._delete_staging_fact_rows('fact_crazy_table', '20190401')

        # assert
        mock_bulk_insert.assert_called_once_with(
            db_enum=EnumDB.BI_DW,
            command="DELETE FROM staging.fact_crazy_table WHERE sk_date = 20190401",
            commit=True,
            encoding='utf-8'
        )

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(LinkedInCampaigns, '_is_staging_table_empty')
    def test__get_staging_table_query_for_dim_table(self, mock__is_staging_table_empty,
                                                    mock__get_query_from_file_name,
                                                    linkedin_campaigns):
        # arrange
        table_name = 'dim_table_1'
        expected_full_load_query = 'full_query'
        mock__get_query_from_file_name.return_value = expected_full_load_query

        # act
        query = linkedin_campaigns._get_staging_table_query(table_name)

        # assert
        mock__get_query_from_file_name.assert_called()
        assert query == expected_full_load_query

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(LinkedInCampaigns, '_is_staging_table_empty')
    @mock.patch.object(LinkedInCampaigns, '_delete_staging_fact_rows')
    def test__get_staging_table_query_for_fact_table(self,
                                                     mock__delete_staging_fact_rows,
                                                     mock__is_staging_table_empty,
                                                     mock__get_query_from_file_name,
                                                     linkedin_campaigns):
        # arrange
        table_name = 'fact_table_1'
        expected_full_load_query = 'full_query'
        mock__get_query_from_file_name.return_value = expected_full_load_query
        mock__is_staging_table_empty.return_value = False
        linkedin_campaigns.execution_date = datetime(2010, 9, 22)

        # act
        query = linkedin_campaigns._get_staging_table_query(table_name)

        # assert
        mock__get_query_from_file_name.assert_called()
        assert query == expected_full_load_query + ' \nWHERE sk_date = 20100922;'

    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(petl, 'fromdataframe')
    def test__load_to_staging(self, mock__fromdataframe, mock__bulk_insert,
                              linkedin_campaigns):
        # arrange
        dw_table_name = 'dim_table_q'
        staging_query = 'cool_query'
        mock_pd_df = MagicMock()
        fn = MagicMock(return_value=mock_pd_df)
        linkedin_campaigns.athena_client.execute_query_and_return_dataframe = fn

        df_table = MagicMock()
        mock__fromdataframe.return_value = df_table

        # act
        linkedin_campaigns._load_to_staging(dw_table_name, staging_query)

        # assert
        linkedin_campaigns.athena_client.execute_query_and_return_dataframe \
            .assert_called_once_with(sql=staging_query)
        mock__fromdataframe.assert_called_once_with(df=mock_pd_df)
        mock__bulk_insert.assert_called_once_with(
            table=df_table,
            table_name='staging.dim_table_q',
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=False,
            commit=True
        )

    @mock.patch.object(LinkedInCampaigns, '_load_to_prod')
    def test_load_to_prod(self, mock__load_to_prod, linkedin_campaigns):
        # arrange
        table_name = 'dim_table'

        # act
        linkedin_campaigns.load_to_prod(table_name)

        # assert
        mock__load_to_prod.assert_called_once_with(table_name)
