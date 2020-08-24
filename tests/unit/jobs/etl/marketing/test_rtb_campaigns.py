from collections import OrderedDict
from datetime import datetime

import mock
import petl
import pytest
from mock import MagicMock, Mock

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl.marketing import RtbCampaigns


class TestRTBCampaigns(object):

    @mock.patch.object(RtbCampaigns, 'get_accounts')
    def test_move_rtb_campaigns_to_raw_with_no_account(
            self, mock_get_accounts, rtb_campaigns):
        # arrange
        mock_get_accounts.return_value = []

        # act
        rtb_campaigns.move_rtb_campaigns_to_raw()

        # assert
        mock_get_accounts.assert_called_once_with()

    @mock.patch.object(RtbCampaigns, 'get_accounts')
    @mock.patch.object(RtbCampaigns, '_fetch_and_save_campaigns')
    @mock.patch.object(RtbCampaigns, '_fetch_and_save_stats')
    def test_move_rtb_campaigns_to_raw(self, mock__fetch_and_save_stats,
                                       mock__fetch_and_save_campaigns,
                                       mock_get_accounts, rtb_campaigns):
        # arrange
        mock_get_accounts.return_value = ['xpto']

        # act
        rtb_campaigns.move_rtb_campaigns_to_raw()

        # assert
        mock_get_accounts.assert_called_once_with()
        mock__fetch_and_save_stats.assert_called_once_with('xpto')
        mock__fetch_and_save_campaigns.assert_called_once_with('xpto')

    @pytest.mark.parametrize('fetched_acounts, expected_accounts', [
        ([], []),
        (['acc1'], ['acc1']),
        (['acc1', 'acc2'], ['acc1', 'acc2'])
    ])
    def test_get_accounts(self, fetched_acounts, expected_accounts, rtb_campaigns):
        # arrange
        mock_rtb_client = Mock()
        mock_rtb_client.get_advertisers.return_value = fetched_acounts
        rtb_campaigns.rtb_client = mock_rtb_client

        # act
        accounts = rtb_campaigns.get_accounts()

        # assert
        rtb_campaigns.rtb_client.get_advertisers.assert_called_once_with()
        assert accounts == expected_accounts

    @pytest.mark.parametrize('campaigns_list, campaigns_list_to_save', [
        ([], []),
        ([{'status': mock.ANY, 'hash': mock.ANY, 'name': mock.ANY,
           'iseditable': mock.ANY, 'ratecardid': mock.ANY, 'updatedat': mock.ANY,
           'placement': mock.ANY, 'creativeIds': mock.ANY}],
         [{'status': mock.ANY, 'hash': mock.ANY, 'name': mock.ANY,
           'iseditable': mock.ANY, 'ratecardid': mock.ANY, 'updatedat': mock.ANY,
           'placement': mock.ANY, 'account_status': mock.ANY,
           'account_hash': mock.ANY, 'account_name': mock.ANY,
           'account_currency': mock.ANY}
          ])
    ])
    @mock.patch.object(RtbCampaigns, '_save_to_s3')
    def test_fetch_and_save_campaigns(self, mock__save_to_s3,
                                      campaigns_list,
                                      campaigns_list_to_save,
                                      rtb_campaigns):
        # arrange
        # campaigns_list = []
        account_hash = 'xpto123'
        account = {'hash': account_hash, 'name': mock.ANY, 'currency': mock.ANY,
                   'status': mock.ANY}

        mock_rtb_client = Mock()
        mock_rtb_client.get_advertiser_campaigns.return_value = campaigns_list
        rtb_campaigns.rtb_client = mock_rtb_client

        # act
        rtb_campaigns._fetch_and_save_campaigns(account)

        # assert
        rtb_campaigns.rtb_client.get_advertiser_campaigns.assert_called_once_with(
            account_hash)
        mock__save_to_s3.assert_called_once_with(account_hash,
                                                 rtb_campaigns.S3_CAMPAIGNS_FOLDER,
                                                 campaigns_list_to_save)

    @mock.patch.object(RtbCampaigns, '_save_to_s3')
    @mock.patch.object(RtbCampaigns, '_get_stats')
    def test__fetch_and_save_stats(self,
                                   mock__get_stats,
                                   mock__save_to_s3, rtb_campaigns):
        # arrange
        mock__get_stats.return_value = [{'foo': 'bar'}]
        account = {'hash': 'xpto123'}

        # act
        rtb_campaigns._fetch_and_save_stats(account)

        # assert
        mock__save_to_s3.assert_called_once_with('xpto123',
                                                 rtb_campaigns.S3_STATS_FOLDER,
                                                 [{'foo': 'bar'}])

    @pytest.mark.parametrize('stats, dpa_stats, expected_stats', [
        ([], [], []),
        ([{'subcampaign': mock.ANY, 'subcampaignhash': mock.ANY, 'deviceType': mock.ANY,
           'day': mock.ANY, 'impsCount': mock.ANY, 'clicksCount': mock.ANY,
           'campaignCost': mock.ANY, 'conversionsCount': mock.ANY,
           'conversionsValue': mock.ANY, 'cr': mock.ANY, 'ctr': mock.ANY,
           'ecc': mock.ANY, 'cpc': mock.ANY, 'roas': mock.ANY, 'ecps': mock.ANY}],
         [
             {'impsCount': mock.ANY, 'clicksCount': mock.ANY, 'ctr': mock.ANY,
              'campaignCost': mock.ANY, 'conversionsCount': mock.ANY,
              'conversionsRate': mock.ANY, 'cpc': mock.ANY, 'ecc': mock.ANY,
              'roas': mock.ANY, 'ecps': mock.ANY, 'conversionsValue': mock.ANY,
              'day': mock.ANY}],
         [
             {'subcampaign': mock.ANY, 'subcampaignhash': mock.ANY,
              'deviceType': mock.ANY, 'day': mock.ANY, 'impsCount': mock.ANY,
              'clicksCount': mock.ANY, 'campaignCost': mock.ANY,
              'conversionsCount': mock.ANY, 'conversionsValue': mock.ANY,
              'cr': mock.ANY, 'ctr': mock.ANY, 'ecc': mock.ANY, 'cpc': mock.ANY,
              'roas': mock.ANY, 'ecps': mock.ANY},
             {'deviceType': 'MOBILE', 'impsCount': mock.ANY, 'clicksCount': mock.ANY,
              'ctr': mock.ANY, 'campaignCost': mock.ANY, 'conversionsCount': mock.ANY,
              'conversionsRate': mock.ANY, 'cpc': mock.ANY, 'ecc': mock.ANY,
              'roas': mock.ANY, 'ecps': mock.ANY, 'conversionsValue': mock.ANY,
              'day': mock.ANY}]),
    ])
    def test__get_stats_with_empty_response(self, stats, dpa_stats, expected_stats,
                                            rtb_campaigns):
        # arrange
        mock_rtb_client = Mock()
        mock_rtb_client.get_rtb_stats.return_value = stats
        mock_rtb_client.get_dpa_campaign_stats.return_value = dpa_stats
        rtb_campaigns.rtb_client = mock_rtb_client

        # act
        stats = rtb_campaigns._get_stats(mock.ANY)

        # assert
        assert stats == expected_stats
        rtb_campaigns.rtb_client.get_rtb_stats.assert_called_once()
        rtb_campaigns.rtb_client.get_dpa_campaign_stats.assert_called_once()

    @mock.patch.object(BaseETL, 'obj_to_s3')
    def test__save_to_s3_with_empty_data(self, mock__obj_to_s3, rtb_campaigns):
        # act
        rtb_campaigns._save_to_s3(mock.ANY, mock.ANY, [])

        # assert
        mock__obj_to_s3.assert_not_called()

    @mock.patch.object(BaseETL, 'obj_to_s3')
    @mock.patch('bietlejuice.jobs.etl.marketing.rtb_campaigns.BytesIO')
    def test__save_to_s3(self, mock__bytes_io, mock__obj_to_s3, rtb_campaigns):
        # arrange
        mocked_bytes_io = MagicMock()
        mock__bytes_io.return_value = mocked_bytes_io

        mock_pendulum = Mock()
        mock_pendulum.strftime = MagicMock(return_value='2017-09-22')
        rtb_campaigns.execution_date = mock_pendulum

        expected_s3_file_path = mock.ANY
        raw_data = [{'abada': 'badoo'}]

        # act
        rtb_campaigns._save_to_s3(mock.ANY, mock.ANY, raw_data)

        # assert
        mock__obj_to_s3.assert_called_with(obj_io=mocked_bytes_io,
                                           bucket=rtb_campaigns.s3_bucket,
                                           file_path=expected_s3_file_path)

    @mock.patch.object(RtbCampaigns, '_move_to_clean')
    def test_move_rtb_stats_to_clean(self, mock__move_to_clean, rtb_campaigns):
        # arrange
        raw_table_query_file = 'stats.sql'
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
            ('conversions_value', str)
        ])

        # act
        rtb_campaigns.move_rtb_stats_to_clean()

        # assert
        mock__move_to_clean.assert_called_once()
        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_rtb_stats',
            sql_file_name=raw_table_query_file,
            r_cols=c_cols,
            c_cols=c_cols)

    @mock.patch.object(RtbCampaigns, '_move_to_clean')
    def test_move_rtb_sub_campaigns_to_clean(self, mock__move_to_clean, rtb_campaigns):
        # arrange
        raw_table_query_file = 'campaigns.sql'
        c_cols = OrderedDict([
            ('hash', str),
            ('name', str),
            ('status', str),
            ('is_editable', str),
            ('rate_card_id', str),
            ('updated_at', str),
            ('account_status', str),
            ('placement', str),
            ('account_hash', str),
            ('account_name', str),
            ('account_currency', str)
        ])

        # act
        rtb_campaigns.move_rtb_sub_campaigns_to_clean()

        # assert
        mock__move_to_clean.assert_called_once()
        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_rtb_sub_campaigns',
            sql_file_name=raw_table_query_file,
            r_cols=c_cols,
            c_cols=c_cols)

    @mock.patch.object(RtbCampaigns, '_get_staging_table_query')
    @mock.patch.object(RtbCampaigns, '_load_to_staging')
    def test_load_to_staging(self, mock__load_to_staging, mock__get_staging_table_query,
                             rtb_campaigns):
        # arrange
        dw_table_name = 'dim_table_c'
        query = 'cool_query'
        mock__get_staging_table_query.return_value = query

        # act
        rtb_campaigns.load_to_staging(dw_table_name)

        # assert
        mock__load_to_staging.assert_called_once_with(dw_table_name, query)

    @mock.patch.object(BaseETL, 'execute_command')
    def test__delete_fact_rows(self, mock_bulk_insert, rtb_campaigns):
        # act
        rtb_campaigns._delete_fact_rows('fact_crazy_table', '20190401')

        # assert
        mock_bulk_insert.assert_called_once_with(
            db_enum=EnumDB.BI_DW,
            command="DELETE FROM staging.fact_crazy_table WHERE sk_date = 20190401",
            commit=True,
            encoding='utf-8'
        )

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(RtbCampaigns, '_is_staging_table_empty')
    def test__get_staging_table_query_for_dim_table(self, mock__is_staging_table_empty,
                                                    mock__get_query_from_file_name,
                                                    rtb_campaigns):
        # arrange
        table_name = 'dim_table_1'
        expected_full_load_query = 'full_query'
        mock__get_query_from_file_name.return_value = expected_full_load_query

        # act
        query = rtb_campaigns._get_staging_table_query(table_name)

        # assert
        mock__get_query_from_file_name.assert_called()
        assert query == expected_full_load_query

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(RtbCampaigns, '_is_staging_table_empty')
    @mock.patch.object(RtbCampaigns, '_delete_fact_rows')
    def test__get_staging_table_query_for_fact_table(self, mock__delete_fact_rows,
                                                     mock__is_staging_table_empty,
                                                     mock__get_query_from_file_name,
                                                     rtb_campaigns):
        # arrange
        table_name = 'fact_table_1'
        expected_full_load_query = 'full_query'
        mock__get_query_from_file_name.return_value = expected_full_load_query
        mock__is_staging_table_empty.return_value = False
        rtb_campaigns.execution_date = datetime(2010, 9, 22)

        # act
        query = rtb_campaigns._get_staging_table_query(table_name)

        # assert
        mock__get_query_from_file_name.assert_called()
        assert query == expected_full_load_query + ' \nWHERE sk_date = 20100922;'

    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(petl, 'fromdataframe')
    def test__load_to_staging(self, mock__fromdataframe, mock__bulk_insert,
                              rtb_campaigns):
        # arrange
        dw_table_name = 'dim_table_q'
        staging_query = 'cool_query'
        mock_pd_df = MagicMock()
        fn = MagicMock(return_value=mock_pd_df)
        rtb_campaigns.athena_client.execute_query_and_return_dataframe = fn

        df_table = MagicMock()
        mock__fromdataframe.return_value = df_table

        # act
        rtb_campaigns._load_to_staging(dw_table_name, staging_query)

        # assert
        rtb_campaigns.athena_client.execute_query_and_return_dataframe \
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

    @mock.patch.object(RtbCampaigns, '_load_to_prod')
    def test_load_to_prod(self, mock__load_to_prod, rtb_campaigns):
        # arrange
        table_name = 'dim_table'

        # act
        rtb_campaigns.load_to_prod(table_name)

        # assert
        mock__load_to_prod.assert_called_once_with(table_name)