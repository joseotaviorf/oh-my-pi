from collections import OrderedDict
from datetime import datetime

import mock
import petl
import pytest
from dateutil.tz import tz
from mock import MagicMock, Mock
from pytest import raises
from twitter_ads.campaign import Campaign
from twitter_ads.creative import PromotedTweet

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl.marketing.twitter_campaigns import TwitterCampaigns


class TestTwitterCampaigns(object):

    @mock.patch.object(TwitterCampaigns, 'get_accounts')
    @mock.patch.object(TwitterCampaigns, '_fetch_and_save_campaigns')
    @mock.patch.object(TwitterCampaigns, '_fetch_and_save_ad_groups')
    @mock.patch.object(TwitterCampaigns, '_fetch_and_save_promoted_tweets')
    @mock.patch.object(TwitterCampaigns, '_fetch_and_save_promoted_tweets_stats')
    def test_move_twitter_ads_to_raw_with_no_account(
            self, mock__fetch_and_save_promoted_tweets_stats,
            mock__fetch_and_save_promoted_tweets, mock__fetch_and_save_ad_groups,
            mock__fetch_and_save_campaigns, mock__get_accounts, twitter_campaigns):
        # arrange
        mock__get_accounts.return_value = []

        # act
        twitter_campaigns.move_twitter_ads_to_raw()

        # assert
        mock__fetch_and_save_campaigns.assert_not_called()
        mock__fetch_and_save_ad_groups.assert_not_called()
        mock__fetch_and_save_promoted_tweets.assert_not_called()
        mock__fetch_and_save_promoted_tweets_stats.assert_not_called()

    @mock.patch.object(TwitterCampaigns, 'get_accounts')
    @mock.patch.object(TwitterCampaigns, '_fetch_and_save_campaigns')
    @mock.patch.object(TwitterCampaigns, '_fetch_and_save_ad_groups')
    @mock.patch.object(TwitterCampaigns, '_fetch_and_save_promoted_tweets')
    @mock.patch.object(TwitterCampaigns, '_fetch_and_save_promoted_tweets_stats')
    def test_move_twitter_ads_to_raw(
            self, mock__fetch_and_save_promoted_tweets_stats,
            mock__fetch_and_save_promoted_tweets, mock__fetch_and_save_ad_groups,
            mock__fetch_and_save_campaigns, mock__get_accounts, twitter_campaigns):
        # arrange
        campaigns_ids = ['c1', 'c2']
        ad_groups_ids = ['ag1', 'ag2']
        prom_twts_ids = ['tw1', 'tw2']
        twitter_campaigns.execution_date = datetime.today()

        acc1 = MagicMock()
        acc2 = MagicMock()
        mock__get_accounts.return_value = [acc1, acc2]

        mock__fetch_and_save_campaigns.return_value = campaigns_ids
        mock__fetch_and_save_ad_groups.return_value = ad_groups_ids
        mock__fetch_and_save_promoted_tweets.return_value = prom_twts_ids

        # act
        twitter_campaigns.move_twitter_ads_to_raw()

        # assert
        mock__fetch_and_save_campaigns.assert_has_calls(
            [mock.call(acc1), mock.call(acc2)])
        mock__fetch_and_save_ad_groups.assert_has_calls(
            [mock.call(acc1, campaigns_ids), mock.call(acc2, campaigns_ids)])
        mock__fetch_and_save_promoted_tweets.assert_has_calls(
            [mock.call(acc1, ad_groups_ids), mock.call(acc2, ad_groups_ids)])
        mock__fetch_and_save_promoted_tweets_stats.assert_has_calls(
            [mock.call(acc1, prom_twts_ids), mock.call(acc2, prom_twts_ids)])

    @mock.patch.object(TwitterCampaigns, '_move_to_clean')
    def test_move_twitter_campaigns_to_clean(self, mock__move_to_clean,
                                             twitter_campaigns):
        # act
        twitter_campaigns.move_twitter_campaigns_to_clean()

        # assert
        raw_table_query_file = 'campaigns.sql'
        raw_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('id_account', str),
            ('account_name', str),
            ('start_time', str),
            ('end_time', str),
            ('created_at', str),
            ('updated_at', str),
            ('entity_status', str),
            ('duration_in_days', str),
            ('total_budget_amount_local_micro', str),
            ('daily_budget_amount_local_micro', str),
            ('standard_delivery', str),
            ('currency', str),
            ('servable', str),
            ('funding_instrument_id', str),
            ('reasons_not_servable', str),
            ('frequency_cap', str),
            ('to_delete', str),
            ('deleted', str)
        ])
        clean_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('id_account', str),
            ('account_name', str),
            ('start_time', str),
            ('end_time', str),
            ('created_at', str),
            ('updated_at', str),
            ('entity_status', str),
            ('duration_in_days', str),
            ('total_budget', str),
            ('daily_budget', str),
            ('standard_delivery', str),
            ('currency', str),
            ('servable', str),
            ('funding_instrument_id', str),
            ('reasons_not_servable', str),
            ('frequency_cap', str),
            ('to_delete', str),
            ('deleted', str)
        ])

        mock__move_to_clean.assert_called_once()
        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_twitter_campaigns',
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=clean_cols)

    @mock.patch.object(TwitterCampaigns, '_move_to_clean')
    def test_move_twitter_ad_groups_to_clean(self, mock__move_to_clean,
                                             twitter_campaigns):
        # act
        twitter_campaigns.move_twitter_ad_groups_to_clean()

        # assert
        raw_table_query_file = 'ad_groups.sql'
        raw_cols = OrderedDict([
            ('id', str),
            ('id_campaign', str),
            ('id_account', str),
            ('name', str),
            ('start_time', str),
            ('end_time', str),
            ('created_at', str),
            ('updated_at', str),
            ('entity_status', str),
            ('total_budget_amount_local_micro', str),
            ('bid_amount_local_micro', str),
            ('automatically_select_bid', str),
            ('bid_type', str),
            ('bid_unit', str),
            ('advertiser_domain', str),
            ('advertiser_user_id', str),
            ('categories', str),
            ('charge_by', str),
            ('include_sentiment', str),
            ('lookalike_expansion', str),
            ('objective', str),
            ('optimization', str),
            ('placements', str),
            ('primary_web_event_tag', str),
            ('product_type', str),
            ('tracking_tags', str),
            ('to_delete', str),
            ('deleted', str)
        ])

        mock__move_to_clean.assert_called_once()
        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_twitter_ad_groups',
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=raw_cols)

    @mock.patch.object(TwitterCampaigns, '_move_to_clean')
    def test_move_twitter_ads_to_clean(self, mock__move_to_clean,
                                       twitter_campaigns):
        # act
        twitter_campaigns.move_twitter_ads_to_clean()

        # assert
        raw_table_query_file = 'ads.sql'
        raw_cols = OrderedDict([
            ('id', str),
            ('id_line_item', str),
            ('id_account', str),
            ('tweet_id', str),
            ('approval_status', str),
            ('created_at', str),
            ('updated_at', str),
            ('deleted', str),
            ('entity_status', str)
        ])

        mock__move_to_clean.assert_called_once()
        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_twitter_ads',
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=raw_cols)

    @mock.patch.object(TwitterCampaigns, '_move_to_clean')
    def test_move_twitter_ads_stats_to_clean(self, mock__move_to_clean,
                                             twitter_campaigns):
        # act
        twitter_campaigns.move_twitter_ads_stats_to_clean()

        # assert
        raw_table_query_file = 'ads_stats.sql'
        raw_cols = OrderedDict([
            ('id_ad', str),
            ('segment_name', str),
            ('segment_value', str),
            ('all_impressions', str),
            ('all_engagements', str),
            ('all_billed_charge_local_micro', str),
            ('all_billed_engagements', str),
            ('all_clicks', str),
            ('all_url_clicks', str),
        ])
        clean_cols = OrderedDict([
            ('id_ad', str),
            ('platform_name', str),
            ('platform_id', str),
            ('impressions', str),
            ('engagements', str),
            ('cost', str),
            ('billed_engagements', str),
            ('clicks', str),
            ('url_clicks', str),
        ])

        mock__move_to_clean.assert_called_once()
        mock__move_to_clean.assert_called_once_with(
            table_name='marketing_twitter_ads_stats',
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=clean_cols)

    @mock.patch.object(BaseETL, 'obj_to_s3')
    @mock.patch('bietlejuice.jobs.etl.marketing.twitter_campaigns.BytesIO')
    def test_save_to_s3(self, mock__bytes_io, mock__obj_to_s3, twitter_campaigns):
        # arrange
        mocked_bytes_io = MagicMock()
        mock__bytes_io.return_value = mocked_bytes_io

        mock_pendulum = Mock()
        mock_pendulum.strftime = MagicMock(return_value='2019-09-22')
        twitter_campaigns.execution_date = mock_pendulum

        account_id = '1a1b1c'
        entity_name = 'ad_groups'
        raw_data = [{'abada': 'badoo'}]
        expected_s3_file_path = '{}/{}/acc={}/dt={}/data.gz'.format(
            twitter_campaigns.S3_DATA_LAKE_RAW_TWITTER_PATH,
            entity_name,
            account_id,
            twitter_campaigns.execution_date.strftime('%Y-%m-%d'))

        # act
        twitter_campaigns._save_to_s3(account_id, entity_name, raw_data)

        # assert
        mock__obj_to_s3.assert_called_with(obj_io=mocked_bytes_io,
                                           bucket=twitter_campaigns.s3_bucket,
                                           file_path=expected_s3_file_path)

    @mock.patch.object(BaseETL, 'obj_to_s3')
    def test_save_to_s3_with_empty_data(self, mock__obj_to_s3, twitter_campaigns):
        # act
        twitter_campaigns._save_to_s3(mock.ANY, mock.ANY, [])

        # assert
        mock__obj_to_s3.assert_not_called()

    def test_get_accounts_with_no_accounts(self, twitter_campaigns):
        # arrange
        mock_accounts = MagicMock()
        mock_accounts.fetched = 0
        twitter_campaigns._twitter_client.accounts = MagicMock(
            return_value=mock_accounts)

        # act
        acc_ids = twitter_campaigns.get_accounts()

        # assert
        assert acc_ids == []

    def test_get_accounts(self, twitter_campaigns):
        # arrange
        mock_accounts = MagicMock()
        mock_accounts.count = 2
        acc1 = MagicMock()
        acc1.id = 3
        acc2 = MagicMock()
        acc2.id = 5
        acc3 = MagicMock()
        acc3.id = 8
        mock_accounts._collection = [acc1, acc2, acc3]
        twitter_campaigns._twitter_client.accounts = MagicMock(
            return_value=mock_accounts)

        # act
        acc_ids = twitter_campaigns.get_accounts()

        # assert
        assert acc_ids._collection == [acc1, acc2, acc3]

    @pytest.mark.parametrize("execution_date,start_date,end_date",
                             [(datetime(2019, 9, 22),
                               datetime(2019, 9, 22, 3, 0, tzinfo=tz.gettz('UTC')),
                               datetime(2019, 9, 23, 3, 0, tzinfo=tz.gettz('UTC'))),
                              (datetime(2018, 2, 28),
                               datetime(2018, 2, 28, 3, 0, tzinfo=tz.gettz('UTC')),
                               datetime(2018, 3, 1, 3, 0, tzinfo=tz.gettz('UTC'))),
                              (datetime(2016, 2, 28),
                               datetime(2016, 2, 28, 3, 0, tzinfo=tz.gettz('UTC')),
                               datetime(2016, 2, 29, 3, 0, tzinfo=tz.gettz('UTC'))),
                              (datetime(2019, 12, 31),
                               datetime(2019, 12, 31, 2, 0, tzinfo=tz.gettz('UTC')),
                               datetime(2020, 1, 1, 2, 0, tzinfo=tz.gettz('UTC')))
                              ])
    def test_get_utc_start_and_end_datetime(self, execution_date, start_date, end_date,
                                            twitter_campaigns):
        """
        Asserts that the function will return the star_date equals execution_date at
        (00:00:00 UTC-3) and end_date equals execution_date+1day at (00:00:00 UTC-3)
        """
        # arrange
        twitter_campaigns.execution_date = execution_date

        # act
        result_start, result_end = twitter_campaigns._get_utc_start_and_end_datetime()

        # assert
        assert result_start == start_date
        assert result_end == end_date

    @mock.patch.object(Campaign, 'active_entities', return_value=[])
    @mock.patch.object(TwitterCampaigns, '_get_utc_start_and_end_datetime',
                       return_value=('2019-09-22T00:00:00Z', '2019-09-23T00:00:00Z'))
    def test_fetch_active_entities_when_entities_are_not_found(self,
                                                               mock___get_utc_dates,
                                                               mock__active_entities,
                                                               twitter_campaigns):
        # arrange
        account = Mock()

        # act
        campaigns_ids = twitter_campaigns._fetch_active_entities(Campaign, account)

        # assert
        mock___get_utc_dates.assert_called_once_with()
        mock__active_entities.assert_called_once_with(account, '2019-09-22T00:00:00Z',
                                                      '2019-09-23T00:00:00Z')
        assert campaigns_ids == []

    @mock.patch.object(Campaign, 'active_entities', return_value=[{
        "entity_id": "2mvb28",
        "activity_start_time": "2019-02-28T01:30:07Z",
        "activity_end_time": "2019-03-01T07:42:55Z",
        "placements": ["ALL_ON_TWITTER"]
    }, {
        "entity_id": "2mvb29",
        "activity_start_time": "2019-02-27T11:30:07Z",
        "activity_end_time": "2019-03-01T07:42:50Z",
        "placements": ["ALL_ON_TWITTER", "PUBLISHER_NETWORK"]
    }])
    @mock.patch.object(TwitterCampaigns, '_get_utc_start_and_end_datetime',
                       return_value=('2018-09-22T00:00:00Z', '2018-09-23T00:00:00Z'))
    def test_fetch_active_entities(self, mock___get_utc_dates, mock__active_entities,
                                   twitter_campaigns):
        # arrange
        account = Mock()

        # act
        campaigns_ids = twitter_campaigns._fetch_active_entities(Campaign, account)

        # assert
        mock___get_utc_dates.assert_called_once_with()
        mock__active_entities.assert_called_once_with(account, '2018-09-22T00:00:00Z',
                                                      '2018-09-23T00:00:00Z')
        assert campaigns_ids == ['2mvb28', '2mvb29']

    @pytest.mark.parametrize("raw_list,expected_chuncked_list",
                             [([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14],
                               [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14]]),
                              (['a', 'b', 'c', 'd', 'e', 'f', 'g'],
                               [['a', 'b', 'c', 'd'], ['e', 'f', 'g']])])
    def test_split_into_chunks(self, raw_list, expected_chuncked_list,
                               twitter_campaigns):
        # act
        chucked_list = twitter_campaigns._split_into_chunks(raw_list, 4)

        # assert
        assert list(chucked_list) == expected_chuncked_list

    def test_get_campaigns_when_no_campaign_is_found(self, twitter_campaigns):
        # arrange
        campaigns_ids = ['aaa', 'bbb', 'ccc']

        campaigns_cursor = MagicMock()
        campaigns_cursor.fetched = 0

        account = MagicMock()
        account.campaigns.return_value = campaigns_cursor

        # act
        campaigns = twitter_campaigns._get_campaigns(account, campaigns_ids)

        # assert
        assert campaigns == []
        account.campaigns.assert_called_once_with(None, campaign_ids='aaa,bbb,ccc')

    def test_get_campaigns(self, twitter_campaigns):
        # arrange
        campaigns_ids = ['aaa']
        mock_campaign = MagicMock()
        mock_campaign.id = 'aaa'
        mock_campaign.name = '2'
        mock_campaign.created_at = '3'
        mock_campaign.updated_at = '4'
        mock_campaign.start_time = '5'
        mock_campaign.end_time = '6'
        mock_campaign.duration_in_days = '7'
        mock_campaign.currency = '8'
        mock_campaign.total_budget_amount_local_micro = '9'
        mock_campaign.daily_budget_amount_local_micro = '10'
        mock_campaign.servable = '11'
        mock_campaign.reasons_not_servable = '12'
        mock_campaign.entity_status = '13'
        mock_campaign.frequency_cap = '14'
        mock_campaign.funding_instrument_id = '15'
        mock_campaign.standard_delivery = '17'
        mock_campaign.to_delete = '18'
        mock_campaign.deleted = '19'

        campaigns_cursor = MagicMock()
        campaigns_cursor.fetched = 1
        campaigns_cursor.__iter__.return_value = [mock_campaign]

        account_id = 'abcd12f'
        account_name = '5a_merchans'
        account = MagicMock()
        account.id = account_id
        account.name = account_name
        account.campaigns.return_value = campaigns_cursor

        # act
        campaigns = twitter_campaigns._get_campaigns(account, campaigns_ids)

        # assert
        expected_campaign = {
            'id': 'aaa',
            'id_account': account_id,
            'account_name': account_name,
            'name': '2',
            'created_at': '3',
            'updated_at': '4',
            'start_time': '5',
            'end_time': '6',
            'duration_in_days': '7',
            'currency': '8',
            'total_budget_amount_local_micro': '9',
            'daily_budget_amount_local_micro': '10',
            'servable': '11',
            'reasons_not_servable': '12',
            'entity_status': '13',
            'frequency_cap': '14',
            'funding_instrument_id': '15',
            'standard_delivery': '17',
            'to_delete': '18',
            'deleted': '19',
        }
        assert campaigns == [expected_campaign]
        account.campaigns.assert_called_once_with(None, campaign_ids='aaa')

    def test_get_ad_groups_when_no_ad_group_is_found(self, twitter_campaigns):
        # arrange
        campaigns_ids = ['aaa', 'bbb', 'ccc']

        line_items_cursor = MagicMock()
        line_items_cursor.fetched = 0

        account = MagicMock()
        account.line_items.return_value = line_items_cursor

        # act
        ad_groups = twitter_campaigns._get_ad_groups(account, campaigns_ids)

        # assert
        assert ad_groups == []
        account.line_items.assert_called_once_with(None, campaign_ids='aaa,bbb,ccc')

    def test_get_ad_groups(self, twitter_campaigns):
        # arrange
        campaigns_ids = ['aaa']
        mock_line_item = MagicMock()
        mock_line_item.id = '1'
        mock_line_item.campaign_id = 'aaa'
        mock_line_item.name = '2'
        mock_line_item.start_time = '3'
        mock_line_item.end_time = '4'
        mock_line_item.created_at = '5'
        mock_line_item.updated_at = '6'
        mock_line_item.advertiser_domain = '7'
        mock_line_item.advertiser_user_id = '8'
        mock_line_item.total_budget_amount_local_micro = '9'
        mock_line_item.automatically_select_bid = '10'
        mock_line_item.bid_amount_local_micro = '11'
        mock_line_item.bid_type = '12'
        mock_line_item.bid_unit = '13'
        mock_line_item.categories = '14'
        mock_line_item.charge_by = '15'
        mock_line_item.entity_status = '16'
        mock_line_item.include_sentiment = '17'
        mock_line_item.lookalike_expansion = '18'
        mock_line_item.objective = '19'
        mock_line_item.optimization = '20'
        mock_line_item.placements = '21'
        mock_line_item.primary_web_event_tag = '22'
        mock_line_item.product_type = '23'
        mock_line_item.tracking_tags = '24'
        mock_line_item.deleted = '25'
        mock_line_item.to_delete = '26'

        line_items_cursor = MagicMock()
        line_items_cursor.fetched = 1
        line_items_cursor.__iter__.return_value = [mock_line_item]

        account_id = 'abcd12g'
        account = MagicMock()
        account.id = account_id
        account.line_items.return_value = line_items_cursor

        # act
        ad_groups = twitter_campaigns._get_ad_groups(account, campaigns_ids)

        # assert
        expected_line_item = {
            'id': '1',
            'id_account': account_id,
            'id_campaign': 'aaa',
            'name': '2',
            'start_time': '3',
            'end_time': '4',
            'created_at': '5',
            'updated_at': '6',
            'advertiser_domain': '7',
            'advertiser_user_id': '8',
            'total_budget_amount_local_micro': '9',
            'automatically_select_bid': '10',
            'bid_amount_local_micro': '11',
            'bid_type': '12',
            'bid_unit': '13',
            'categories': '14',
            'charge_by': '15',
            'entity_status': '16',
            'include_sentiment': '17',
            'lookalike_expansion': '18',
            'objective': '19',
            'optimization': '20',
            'placements': '21',
            'primary_web_event_tag': '22',
            'product_type': '23',
            'tracking_tags': '24',
            'deleted': '25',
            'to_delete': '26'
        }
        assert ad_groups == [expected_line_item]
        account.line_items.assert_called_once_with(None, campaign_ids='aaa')

    def test_get_promoted_tweets_when_no_ad_group_id_found(self, twitter_campaigns):
        # arrange
        ad_groups_ids = ['aaa', 'bbb', 'ccc']

        prom_tweets_cursor = MagicMock()
        prom_tweets_cursor.fetched = 0

        account = MagicMock()
        account.promoted_tweets.return_value = prom_tweets_cursor

        # act
        prom_tweets = twitter_campaigns._get_promoted_tweets(account, ad_groups_ids)

        # assert
        assert prom_tweets == []
        account.promoted_tweets.assert_called_once_with(None,
                                                        line_item_ids='aaa,bbb,ccc')

    def test_get_promoted_tweets(self, twitter_campaigns):
        # arrange
        ad_groups_ids = ['aaa']
        mock_prom_tweet = MagicMock()
        mock_prom_tweet.id = '1'
        mock_prom_tweet.line_item_id = 'aaa'
        mock_prom_tweet.tweet_id = '3'
        mock_prom_tweet.approval_status = '4'
        mock_prom_tweet.created_at = '5'
        mock_prom_tweet.updated_at = '6'
        mock_prom_tweet.deleted = '7'
        mock_prom_tweet.entity_status = '8'

        prom_tweets_cursor = MagicMock()
        prom_tweets_cursor.fetched = 1
        prom_tweets_cursor.__iter__.return_value = [mock_prom_tweet]

        account_id = 'abcd12g'
        account = MagicMock()
        account.id = account_id
        account.promoted_tweets.return_value = prom_tweets_cursor

        # act
        prom_tweets = twitter_campaigns._get_promoted_tweets(account, ad_groups_ids)

        # assert
        expected_prom_tweet = {
            'id': '1',
            'id_account': account_id,
            'id_line_item': 'aaa',
            'tweet_id': '3',
            'approval_status': '4',
            'created_at': '5',
            'updated_at': '6',
            'deleted': '7',
            'entity_status': '8',
        }
        assert prom_tweets == [expected_prom_tweet]
        account.promoted_tweets.assert_called_once_with(None, line_item_ids='aaa')

    @mock.patch.object(TwitterCampaigns, '_fetch_active_entities', return_value=[])
    def test_fetch_and_save_campaigns_with_no_active_campaigns(
            self,
            mock__fetch_active_entities,
            twitter_campaigns):
        # arrange
        account = Mock()

        # act
        ids_list = twitter_campaigns._fetch_and_save_campaigns(account)

        # assert
        assert ids_list == []

    @mock.patch.object(TwitterCampaigns, '_fetch_active_entities',
                       return_value=['aaa', 'bbb', 'ccc', 'ddd'])
    @mock.patch.object(TwitterCampaigns, '_get_campaigns',
                       return_value=[{'id': 'aaa'}, {'id': 'bbb'}, {'id': 'ccc'}])
    @mock.patch.object(TwitterCampaigns, '_save_to_s3')
    def test_fetch_and_save_campaigns(self, mock__save_to_s3, mock__get_campaigns,
                                      mock__fetch_active_entities, twitter_campaigns):
        # arrange
        account = Mock()

        # act
        ids_list = twitter_campaigns._fetch_and_save_campaigns(account)

        # assert
        assert ids_list == ['aaa', 'bbb', 'ccc']

    @mock.patch.object(TwitterCampaigns, '_get_ad_groups', return_value=[])
    @mock.patch.object(TwitterCampaigns, '_save_to_s3')
    def test_fetch_and_save_ad_groups_with_no_active_ad_groups(self, mock__save_to_s3,
                                                               mock__get_ad_groups,
                                                               twitter_campaigns):
        # arrange
        account = Mock()
        account.id = 'abdj122'
        campaigns_ids = ['zzz', 'yyy']

        # act
        ad_groups_ids = twitter_campaigns._fetch_and_save_ad_groups(account,
                                                                    campaigns_ids)

        # assert
        assert ad_groups_ids == []
        mock__get_ad_groups.assert_called_once_with(account, campaigns_ids)
        mock__save_to_s3.assert_called_once_with(
            account.id,
            twitter_campaigns.S3_LINE_ITEMS_FOLDER,
            [])

    @mock.patch.object(TwitterCampaigns, '_get_ad_groups',
                       return_value=[{'id': 'aaa'}, {'id': 'bbb'}, {'id': 'ccc'}])
    @mock.patch.object(TwitterCampaigns, '_save_to_s3')
    def test_fetch_and_save_ad_groups(self, mock__save_to_s3, mock__get_ad_groups,
                                      twitter_campaigns):
        # arrange
        account = Mock()
        account.id = 'abdj122'
        campaigns_ids = ['zzz', 'yyy']

        # act
        ad_groups_ids = twitter_campaigns._fetch_and_save_ad_groups(account,
                                                                    campaigns_ids)

        # assert
        assert ad_groups_ids == ['aaa', 'bbb', 'ccc']
        mock__get_ad_groups.assert_called_once_with(account, campaigns_ids)
        mock__save_to_s3.assert_called_once_with(
            account.id,
            twitter_campaigns.S3_LINE_ITEMS_FOLDER,
            [{'id': 'aaa'}, {'id': 'bbb'}, {'id': 'ccc'}])

    @mock.patch.object(TwitterCampaigns, '_get_promoted_tweets', return_value=[])
    @mock.patch.object(TwitterCampaigns, '_save_to_s3')
    def test_fetch_and_save_promoted_tweets_with_no_active_prom_twts(
            self,
            mock__save_to_s3,
            mock__get_promoted_tweets,
            twitter_campaigns):
        # arrange
        account = Mock()
        account.id = 'abdj122'
        ad_groups_ids = ['xxx', 'jjj']

        # act
        prom_tweets_ids = twitter_campaigns._fetch_and_save_promoted_tweets(account,
                                                                            ad_groups_ids)

        # assert
        assert prom_tweets_ids == []
        mock__get_promoted_tweets.assert_called_once_with(account, ad_groups_ids)
        mock__save_to_s3.assert_called_once_with(
            account.id,
            twitter_campaigns.S3_PROMOTED_TWEETS_FOLDER,
            [])

    @mock.patch.object(TwitterCampaigns, '_get_promoted_tweets',
                       return_value=[{'id': 'aaa'}, {'id': 'bbb'}, {'id': 'ccc'}])
    @mock.patch.object(TwitterCampaigns, '_save_to_s3')
    def test_fetch_and_save_promoted_tweets_with_no_active_prom_twts(
            self,
            mock__save_to_s3,
            mock__get_promoted_tweets,
            twitter_campaigns):
        # arrange
        account = Mock()
        account.id = 'abdj122'
        ad_groups_ids = ['xxx', 'jjj']

        # act
        prom_tweets_ids = twitter_campaigns._fetch_and_save_promoted_tweets(account,
                                                                            ad_groups_ids)

        # assert
        assert prom_tweets_ids == ['aaa', 'bbb', 'ccc']
        mock__get_promoted_tweets.assert_called_once_with(account, ad_groups_ids)
        mock__save_to_s3.assert_called_once_with(
            account.id,
            twitter_campaigns.S3_PROMOTED_TWEETS_FOLDER,
            [{'id': 'aaa'}, {'id': 'bbb'}, {'id': 'ccc'}])

    @mock.patch.object(Campaign, 'async_stats_job_result')
    def test_fetch_jobs_result_with_api_fail(self, mock__async_stats_job_result,
                                             twitter_campaigns):
        # arrange
        twitter_campaigns._JOB_WAIT_SECONDS = 0.1
        twitter_campaigns._JOB_STATUS_MAX_TRIES = 2

        jobs_result = {'url': 'lorem.com'}
        mock__async_stats_job_result.return_value = {}

        # assert
        with raises(RuntimeError):
            # act
            twitter_campaigns._fetch_jobs_result(Mock(), 'job_1_id', 'job_2_id')

    @mock.patch.object(Campaign, 'async_stats_job_result')
    def test_fetch_jobs_result(self, mock__async_stats_job_result, twitter_campaigns):
        # arrange
        twitter_campaigns._JOB_WAIT_SECONDS = 0.1
        jobs_result = {'url': 'lorem.com'}
        mock__async_stats_job_result.return_value = jobs_result

        # act
        result = twitter_campaigns._fetch_jobs_result(Mock(), 'job_1_id', 'job_2_id')

        # assert
        assert result == (jobs_result, jobs_result)

    @mock.patch.object(PromotedTweet, 'queue_async_stats_job')
    def test_queue_async_stats_job(self, mock__queue_async_stats_job,
                                   twitter_campaigns):
        # arrange
        account = Mock()
        _ids = [1, 2, 3, 4]
        metric_groups = 'bla'
        granularity = 'foo'
        placement = 'ios'
        start_time = '1'
        end_time = '2'
        segmentation_type = 'ipsum'

        # act
        twitter_campaigns._queue_async_stats_job(account, _ids, metric_groups,
                                                 granularity,
                                                 placement, start_time, end_time,
                                                 segmentation_type)

        # assert
        mock__queue_async_stats_job.assert_called_once_with(
            account, _ids, metric_groups, granularity=granularity, placement=placement,
            segmentation_type=segmentation_type, start_time=start_time,
            end_time=end_time)

    @mock.patch.object(TwitterCampaigns, '_get_utc_start_and_end_datetime',
                       return_value=('2019-01-28T03:00:00Z', '2019-01-29T03:00:00Z'))
    @mock.patch.object(TwitterCampaigns, '_save_to_s3')
    def test_fetch_and_save_promoted_tweets_stats_with_empty_list(self,
                                                                  mock__save_to_s3,
                                                                  mock__get_dates,
                                                                  twitter_campaigns):
        # arrange
        account = MagicMock()
        account.id = 'ab123'

        # act
        twitter_campaigns._fetch_and_save_promoted_tweets_stats(account, [])

        # assert
        mock__save_to_s3.assert_called_once_with(
            account.id,
            twitter_campaigns.S3_PROMOTED_TWEETS_STATS_FOLDER,
            [])

    @mock.patch.object(TwitterCampaigns, '_get_utc_start_and_end_datetime',
                       return_value=('2019-01-28T03:00:00Z', '2019-01-29T03:00:00Z'))
    @mock.patch.object(TwitterCampaigns, '_save_to_s3')
    @mock.patch.object(TwitterCampaigns, '_queue_async_stats_job')
    @mock.patch.object(TwitterCampaigns, '_fetch_jobs_result')
    @mock.patch.object(PromotedTweet, 'async_stats_job_data')
    @mock.patch.object(TwitterCampaigns, '_merge_placements_stats')
    def test_fetch_and_save_promoted_tweets_stats_with_empty_list(
            self, mock__merge_placements_stats, mock_async_stats_job_data,
            mock__fetch_jobs_result, mock__queue_async_stats_job, mock__save_to_s3,
            mock__get_utc_start_and_end_datetime, twitter_campaigns):
        # arrange
        account = MagicMock()
        account.id = 'ab123'
        prom_tweets_ids = ['aaa1']
        mock__fetch_jobs_result.return_value = {'url': None}, {'url': None}
        prom_tweets_list = [Mock(), Mock(), Mock()]
        mock__merge_placements_stats.return_value = prom_tweets_list

        # act
        twitter_campaigns._fetch_and_save_promoted_tweets_stats(account,
                                                                prom_tweets_ids)

        # assert
        mock__save_to_s3.assert_called_once_with(
            account.id, twitter_campaigns.S3_PROMOTED_TWEETS_STATS_FOLDER,
            prom_tweets_list)

    def test_merge_placements_stats(self, twitter_campaigns):
        # arrange
        twt_stats_1 = {
            'id': '3344aa',
            'id_data': [{
                'metrics': {
                    'carousel_swipes': 1,
                    'likes': 2,
                    'poll_card_vote': 3,
                    'follows': 4,
                    'app_clicks': 5,
                    'billed_engagements': [6],
                    'card_engagements': 7,
                    'qualified_impressions': 8,
                    'url_clicks': [9],
                    'retweets': 10,
                    'replies': 11,
                    'tweets_send': 12,
                    'impressions': [13],
                    'engagements': [14],
                    'unfollows': 15,
                    'clicks': [16],
                    'billed_charge_local_micro': [17]
                },
                'segment': {
                    'segment_value': '18',
                    'segment_name': '19'
                }
            }]
        }
        twt_stats_2 = {
            'id': '668aa',
            'id_data': [{
                'metrics': {
                    'carousel_swipes': 1,
                    'likes': 2,
                    'poll_card_vote': 3,
                    'follows': 4,
                    'app_clicks': 5,
                    'billed_engagements': [6],
                    'card_engagements': 7,
                    'qualified_impressions': 8,
                    'url_clicks': [9],
                    'retweets': 10,
                    'replies': 11,
                    'tweets_send': 12,
                    'impressions': [13],
                    'engagements': [14],
                    'unfollows': 15,
                    'clicks': [16],
                    'billed_charge_local_micro': [17]
                },
                'segment': {
                    'segment_value': '18',
                    'segment_name': '19'
                }
            }]
        }
        all_on_twitter_stats = {'data': [twt_stats_1]}
        publisher_network_stats = {'data': [twt_stats_2]}

        # act
        twts_list = twitter_campaigns._merge_placements_stats(all_on_twitter_stats,
                                                              publisher_network_stats)

        # assert
        expected_dict1 = {
            'id_ad': '3344aa',
            'all_on_twitter_carousel_swipes': 1,
            'all_on_twitter_likes': 2,
            'all_on_twitter_poll_card_vote': 3,
            'all_on_twitter_follows': 4,
            'all_on_twitter_app_clicks': 5,
            'all_on_twitter_billed_engagements': [6],
            'all_on_twitter_card_engagements': 7,
            'all_on_twitter_qualified_impressions': 8,
            'all_on_twitter_url_clicks': [9],
            'all_on_twitter_retweets': 10,
            'all_on_twitter_replies': 11,
            'all_on_twitter_tweets_send': 12,
            'all_on_twitter_impressions': [13],
            'all_on_twitter_engagements': [14],
            'all_on_twitter_unfollows': 15,
            'all_on_twitter_clicks': [16],
            'all_on_twitter_billed_charge_local_micro': [17],
            'segment_name': '19',
            'segment_value': '18'
        }
        expected_dict2 = {
            'id_ad': '668aa',
            'publisher_network_segment_carousel_swipes': 1,
            'publisher_network_segment_likes': 2,
            'publisher_network_segment_poll_card_vote': 3,
            'publisher_network_segment_follows': 4,
            'publisher_network_segment_app_clicks': 5,
            'publisher_network_segment_billed_engagements': [6],
            'publisher_network_segment_card_engagements': 7,
            'publisher_network_segment_qualified_impressions': 8,
            'publisher_network_segment_url_clicks': [9],
            'publisher_network_segment_retweets': 10,
            'publisher_network_segment_replies': 11,
            'publisher_network_segment_tweets_send': 12,
            'publisher_network_segment_impressions': [13],
            'publisher_network_segment_engagements': [14],
            'publisher_network_segment_unfollows': 15,
            'publisher_network_segment_clicks': [16],
            'publisher_network_segment_billed_charge_local_micro': [17],
            'segment_name': '19',
            'segment_value': '18'
        }
        assert twts_list == [expected_dict1, expected_dict2]

    @mock.patch.object(TwitterCampaigns, '_get_staging_table_query')
    @mock.patch.object(TwitterCampaigns, '_load_to_staging')
    def test_load_to_staging(self, mock__load_to_staging, mock__get_staging_table_query,
                             twitter_campaigns):
        # arrange
        dw_table_name = 'dim_table_c'
        query = 'cool_query'
        mock__get_staging_table_query.return_value = query

        # act
        twitter_campaigns.load_to_staging(dw_table_name)

        # assert
        mock__load_to_staging.assert_called_once_with(dw_table_name, query)

    @mock.patch.object(BaseETL, 'execute_command')
    def test__delete_fact_rows(self, mock_bulk_insert, twitter_campaigns):
        # act
        twitter_campaigns._delete_fact_rows('fact_crazy_table', '20190401')

        # assert
        mock_bulk_insert.assert_called_once_with(
            db_enum=EnumDB.BI_DW,
            command="DELETE FROM staging.fact_crazy_table WHERE sk_date = 20190401",
            commit=True,
            encoding='utf-8'
        )

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(TwitterCampaigns, '_is_staging_table_empty')
    def test__get_staging_table_query_for_dim_table(self, mock__is_staging_table_empty,
                                                    mock__get_query_from_file_name,
                                                    twitter_campaigns):
        # arrange
        table_name = 'dim_table_1'
        expected_full_load_query = 'full_query'
        mock__get_query_from_file_name.return_value = expected_full_load_query

        # act
        query = twitter_campaigns._get_staging_table_query(table_name)

        # assert
        mock__get_query_from_file_name.assert_called()
        assert query == expected_full_load_query

    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    @mock.patch.object(TwitterCampaigns, '_is_staging_table_empty')
    @mock.patch.object(TwitterCampaigns, '_delete_fact_rows')
    def test__get_staging_table_query_for_fact_table(self, mock__delete_fact_rows,
                                                     mock__is_staging_table_empty,
                                                     mock__get_query_from_file_name,
                                                     twitter_campaigns):
        # arrange
        table_name = 'fact_table_1'
        expected_full_load_query = 'full_query'
        mock__get_query_from_file_name.return_value = expected_full_load_query
        mock__is_staging_table_empty.return_value = False
        twitter_campaigns.execution_date = datetime(2010, 9, 22)

        # act
        query = twitter_campaigns._get_staging_table_query(table_name)

        # assert
        mock__get_query_from_file_name.assert_called()
        assert query == expected_full_load_query + ' \nWHERE sk_date = 20100922;'

    @mock.patch.object(BaseETL, 'bulk_insert')
    @mock.patch.object(petl, 'fromdataframe')
    def test__load_to_staging(self, mock__fromdataframe, mock__bulk_insert,
                              twitter_campaigns):
        # arrange
        dw_table_name = 'dim_table_q'
        staging_query = 'cool_query'
        mock_pd_df = MagicMock()
        fn = MagicMock(return_value=mock_pd_df)
        twitter_campaigns.athena_client.execute_query_and_return_dataframe = fn

        df_table = MagicMock()
        mock__fromdataframe.return_value = df_table

        # act
        twitter_campaigns._load_to_staging(dw_table_name, staging_query)

        # assert
        twitter_campaigns.athena_client.execute_query_and_return_dataframe \
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

    @mock.patch.object(TwitterCampaigns, '_load_to_prod')
    def test_load_to_prod(self, mock__load_to_prod, twitter_campaigns):
        # arrange
        table_name = 'dim_table'

        # act
        twitter_campaigns.load_to_prod(table_name)

        # assert
        mock__load_to_prod.assert_called_once_with(table_name)
