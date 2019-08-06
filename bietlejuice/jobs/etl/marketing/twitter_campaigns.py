import json
import time
from collections import OrderedDict
from datetime import datetime, timedelta
from gzip import GzipFile
from io import BytesIO

from dateutil.tz import tz
from qa_python_utils.default_logger import QuintoAndarLogger
from twitter_ads.campaign import Campaign
from twitter_ads.client import Client as TwitterClient
from twitter_ads.creative import PromotedTweet
from twitter_ads.enum import METRIC_GROUP, GRANULARITY, PLACEMENT

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.marketing import Marketing

logger = QuintoAndarLogger('TwitterCampaigns')


class TwitterCampaigns(Marketing):
    S3_CAMPAIGNS_FOLDER = 'campaigns'
    S3_LINE_ITEMS_FOLDER = 'ad_groups'
    S3_PROMOTED_TWEETS_FOLDER = 'ads'
    S3_PROMOTED_TWEETS_STATS_FOLDER = 'ads_stats'
    S3_TWITTER_FOLDER = 'twitter_ads'
    S3_DATA_LAKE_RAW_TWITTER_PATH = 'raw/marketing/{}'.format(S3_TWITTER_FOLDER)
    CAMPAIGNS_TABLE_NAME = "twitter_campaigns"
    AD_GROUPS_TABLE_NAME = 'twitter_ad_groups'
    ADS_TABLE_NAME = "twitter_ads"
    ADS_STATS_TABLE_NAME = "twitter_ads_stats"

    def __init__(self, s3_bucket, execution_date, auth, account=None):
        """
        The consumer_key, consumer_secret, access_token, and access_token_secret can
        be found on Twitter Developer console:
        https://developer.twitter.com/en/apps/16579094
        """
        super(TwitterCampaigns, self).__init__(s3_bucket, execution_date,
                                               self.S3_TWITTER_FOLDER, account)

        self._twitter_client = TwitterClient(auth['consumer_key'],
                                             auth['consumer_secret'],
                                             auth['access_token'],
                                             auth['access_token_secret'])
        self._JOB_WAIT_SECONDS = 15
        self._JOB_STATUS_MAX_TRIES = 10

    @logger
    def move_twitter_ads_to_raw(self):
        """
        Fetch all accounts on Twitter Ads platform and save all its Campaigns, AdGroups,
        Promoted Tweets details and Promoted Tweets stats on data lake raw
        """

        for acc in self.get_accounts():
            campaigns_ids = self._fetch_and_save_campaigns(acc)
            ad_groups_ids = self._fetch_and_save_ad_groups(acc, campaigns_ids)
            prom_twts_ids = self._fetch_and_save_promoted_tweets(acc, ad_groups_ids)
            self._fetch_and_save_promoted_tweets_stats(acc, prom_twts_ids)

    @logger
    def move_twitter_campaigns_to_clean(self):
        """
        Here it's mapped raw and clean columns and the sql file which will be used to
        execute the query on Athena raw table.
        The raw_cols maps raw_table_query_file result columns and the clean_cols maps the
        columns on parquet. The raw_cols and clean_cols should have corresponding
        columns at the same index
        """
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

        self._move_to_clean(
            table_name='marketing_' + self.CAMPAIGNS_TABLE_NAME,
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=clean_cols
        )

    @logger
    def move_twitter_ad_groups_to_clean(self):
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

        self._move_to_clean(
            table_name='marketing_' + self.AD_GROUPS_TABLE_NAME,
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=raw_cols
        )

    @logger
    def move_twitter_ads_to_clean(self):
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

        self._move_to_clean(
            table_name='marketing_' + self.ADS_TABLE_NAME,
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=raw_cols
        )

    @logger
    def move_twitter_ads_stats_to_clean(self):
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

        self._move_to_clean(
            table_name='marketing_' + self.ADS_STATS_TABLE_NAME,
            sql_file_name=raw_table_query_file,
            r_cols=raw_cols,
            c_cols=clean_cols
        )

    @logger(exclude='raw_data')
    def _save_to_s3(self, id_account, entity_name, raw_data):
        """
            This method saves the json on the datalake raw as a compacted gzip file
            Every row is broken in lines, so that Athena will compute
        """
        logger.info('m=_save_to_s3')

        gz_body = BytesIO()
        for _dict in raw_data:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_dict, ensure_ascii=False)).encode('utf-8'))
                fp.write('\n')

        s3_file_path = '{}/{}/acc={}/dt={}/data.gz'.format(
            self.S3_DATA_LAKE_RAW_TWITTER_PATH,
            entity_name,
            id_account,
            self.execution_date.strftime('%Y-%m-%d'))

        logger.info(
            'm=_save_to_s3, dest={}, msg=Saving twitter data into s3 bucket'.format(
                s3_file_path))

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
    def get_accounts(self):
        """
        Fetches QuintoAndar accounts at ads.twitter.com
        :return: twitter_ads.cursor.Cursor with found accounts
        """
        accounts = self._twitter_client.accounts()
        if accounts.fetched == 0:
            logger.info('m=get_accounts, msg=No ads accounts found')
            return []

        return accounts

    @logger
    def _get_utc_start_and_end_datetime(self):
        """
        Return start and end datetime based on Airflow execution date.

        Start time will be the execution date and end time will be the start plus 1 day.
        Both dates time are at UTC 03:00 (corresponding to UTC-3 time 00:00), thus we
        can search for the exact day at BR time.

        :return: start_time_utc, end_time_utc
        """
        utc_tz = tz.gettz('UTC')
        sp_tz = tz.gettz('America/Sao_Paulo')

        str_execution_date = self.execution_date.strftime('%Y-%m-%d')
        execution_date = datetime.strptime(str_execution_date, "%Y-%m-%d")
        execution_date_sp_tz = execution_date.replace(hour=0, minute=0, second=0,
                                                      microsecond=0, tzinfo=sp_tz)
        start_time_utc = execution_date_sp_tz.astimezone(utc_tz)
        end_time_utc = start_time_utc + timedelta(days=1)

        return start_time_utc, end_time_utc

    @logger
    def _fetch_active_entities(self, entity_class, account):
        """
        Checks the active entities of type entity_class for the start_time to end_time

        :return: Entities ids list, searching start and end dates
        """
        start_time, end_time = self._get_utc_start_and_end_datetime()
        logger.info('m=_fetch_active_entities, entity={}, startTime={}, endTime={}'
                    ' msg=Fetching active entities'.format(str(entity_class),
                                                           start_time, end_time))

        active_entities = entity_class.active_entities(account, start_time, end_time)

        logger.info('m=_fetch_active_entities, msg={} active entities found'.format(
            len(active_entities)))

        entities_ids = [d['entity_id'] for d in active_entities]

        return entities_ids

    @staticmethod
    def _split_into_chunks(raw_list, chunk_size):
        for i in range(0, len(raw_list), chunk_size):
            yield raw_list[i:i + chunk_size]

    @logger(exclude='campaigns_ids')
    def _get_campaigns(self, account, campaigns_ids):
        """
        Retrieve campaigns and its details for given campaign_ids.
        Doc: https://developer.twitter.com/en/docs/ads/campaign-management/api-reference/campaigns

        :return: List with campaigns dicts
        """

        # the api accepts a max of 200 ids per request
        batch_ids = self._split_into_chunks(campaigns_ids, 200)

        campaigns_list = []
        for ids in batch_ids:
            params = {'campaign_ids': ",".join(str(c_id) for c_id in ids)}
            campaigns_cursor = account.campaigns(None, **params)

            if campaigns_cursor.fetched == 0:
                logger.info(
                    'm=_get_campaigns_details, msg=No details were found for the '
                    'active campaign_ids: {}'.format(str(ids)))
            else:
                for campaign in campaigns_cursor:
                    campaign_details = {
                        'id': campaign.id,
                        'id_account': account.id,
                        'account_name': account.name,
                        'name': campaign.name,
                        'created_at': campaign.created_at,
                        'updated_at': campaign.updated_at,
                        'start_time': campaign.start_time,
                        'end_time': campaign.end_time,
                        'duration_in_days': campaign.duration_in_days,
                        'currency': campaign.currency,
                        'total_budget_amount_local_micro': campaign.total_budget_amount_local_micro,
                        'daily_budget_amount_local_micro': campaign.daily_budget_amount_local_micro,
                        'servable': campaign.servable,
                        'reasons_not_servable': campaign.reasons_not_servable,
                        'entity_status': campaign.entity_status,
                        'frequency_cap': campaign.frequency_cap,
                        'funding_instrument_id': campaign.funding_instrument_id,
                        'standard_delivery': campaign.standard_delivery,
                        'to_delete': campaign.to_delete,
                        'deleted': campaign.deleted
                    }

                    campaigns_list.append(campaign_details)

        return campaigns_list

    @logger
    def _get_ad_groups(self, account, campaigns_ids):
        """
        Retrieve the AdGroups for given campaigns ids.
        Note: On Twitter API AdGroups are named as LineItem
        Doc: https://developer.twitter.com/en/docs/ads/campaign-management/api-reference/line-items

        :return: List with AdGroups dicts
        """

        # the api accepts a max of 200 ids per request
        batch_ids = self._split_into_chunks(campaigns_ids, 200)

        ad_groups_list = []
        for ids in batch_ids:
            params = {'campaign_ids': ",".join(str(c_id) for c_id in ids)}
            line_items_cursor = account.line_items(None, **params)

            if line_items_cursor.fetched == 0:
                logger.info(
                    'm=_get_ad_groups, msg=No AdGroups were found for the '
                    'campaign_ids: {}'.format(str(ids)))
            else:
                for line_item in line_items_cursor:
                    line_item_details = {
                        'id': line_item.id,
                        'id_campaign': line_item.campaign_id,
                        'id_account': account.id,
                        'name': line_item.name,
                        'start_time': line_item.start_time,
                        'end_time': line_item.end_time,
                        'created_at': line_item.created_at,
                        'updated_at': line_item.updated_at,
                        'advertiser_domain': line_item.advertiser_domain,
                        'advertiser_user_id': line_item.advertiser_user_id,
                        'total_budget_amount_local_micro': line_item.total_budget_amount_local_micro,
                        'automatically_select_bid': line_item.automatically_select_bid,
                        'bid_amount_local_micro': line_item.bid_amount_local_micro,
                        'bid_type': line_item.bid_type,
                        'bid_unit': line_item.bid_unit,
                        'categories': line_item.categories,
                        'charge_by': line_item.charge_by,
                        'entity_status': line_item.entity_status,
                        'include_sentiment': line_item.include_sentiment,
                        'lookalike_expansion': line_item.lookalike_expansion,
                        'objective': line_item.objective,
                        'optimization': line_item.optimization,
                        'placements': line_item.placements,
                        'primary_web_event_tag': line_item.primary_web_event_tag,
                        'product_type': line_item.product_type,
                        'tracking_tags': line_item.tracking_tags,
                        'deleted': line_item.deleted,
                        'to_delete': line_item.to_delete,

                    }
                    ad_groups_list.append(line_item_details)

        return ad_groups_list

    @logger
    def _get_promoted_tweets(self, account, ad_groups_ids):
        """
        Retrieve the promoted tweets for given AdGroups ids.

        Doc: https://developer.twitter.com/en/docs/ads/campaign-management/api-reference/promoted-tweets

        :return: List with Promoted Tweets dicts
        """

        # the api accepts a max of 200 ids per request
        batch_ids = self._split_into_chunks(ad_groups_ids, 200)

        prom_tweets_list = []
        for ids in batch_ids:
            params = {'line_item_ids': ",".join(str(li_id) for li_id in ids)}
            prom_tweets_cursor = account.promoted_tweets(None, **params)

            if prom_tweets_cursor.fetched == 0:
                logger.info(
                    'm=_get_promoted_tweets, msg=No promoted tweets were found for the '
                    'line_items_ids: {}'.format(str(ids)))
            else:
                for prom_tweet in prom_tweets_cursor:
                    prom_tweet_details = {
                        'id': prom_tweet.id,
                        'id_line_item': prom_tweet.line_item_id,
                        'id_account': account.id,
                        'tweet_id': prom_tweet.tweet_id,
                        'approval_status': prom_tweet.approval_status,
                        'created_at': prom_tweet.created_at,
                        'updated_at': prom_tweet.updated_at,
                        'deleted': prom_tweet.deleted,
                        'entity_status': prom_tweet.entity_status
                    }
                    prom_tweets_list.append(prom_tweet_details)

        return prom_tweets_list

    @logger
    def _fetch_and_save_campaigns(self, account):
        """
        Fetches active campaigns from the period and saves on the datalake by account

        :param account: account from type twitter_ads.account.Account
        :return: List with account campaigns ids
        """
        campaigns_ids = self._fetch_active_entities(Campaign, account)
        if not campaigns_ids:
            return []

        campaigns_list = self._get_campaigns(account, campaigns_ids)
        self._save_to_s3(account.id, self.S3_CAMPAIGNS_FOLDER, campaigns_list)

        ids_list = []
        ids_list += [campaign['id'] for campaign in campaigns_list]

        logger.info('m=_fetch_and_save_campaigns, msg=Found {} '
                    'campaigns.'.format(str(ids_list)))

        return ids_list

    @logger(exclude='campaigns_ids')
    def _fetch_and_save_ad_groups(self, account, campaigns_ids):
        """
        Fetches AdGroups from the period and saves on the datalake by account

        :param account: account from type twitter_ads.account.Account
        :param campaigns_ids: Campaigns ids list to filter ad_groups
        :return: List with all campaigns ids
        """

        ad_groups_list = self._get_ad_groups(account, campaigns_ids)
        self._save_to_s3(account.id, self.S3_LINE_ITEMS_FOLDER, ad_groups_list)

        ad_groups_ids = []
        ad_groups_ids += [ad_group['id'] for ad_group in ad_groups_list]

        logger.info('m=_fetch_and_save_ad_groups, msg=Found {} '
                    'ad_groups.'.format(len(ad_groups_ids)))

        return ad_groups_ids

    @logger(exclude='ad_groups_ids')
    def _fetch_and_save_promoted_tweets(self, account, ad_groups_ids):
        """
        Fetches promoted_tweets(ads) from the period and saves on the datalake by account

        :param account: account from type twitter_ads.account.Account
        :param ad_groups_ids: AdGroups ids list to filter promoted tweets
        :return: List with all promoted tweets ids (the API Promoted Tweet ID is not the
        same of the Tweet ID on users frontend)
        """

        prom_tweets_list = self._get_promoted_tweets(account, ad_groups_ids)
        self._save_to_s3(account.id, self.S3_PROMOTED_TWEETS_FOLDER, prom_tweets_list)

        prom_tweets_ids = []
        prom_tweets_ids += [pt['id'] for pt in prom_tweets_list]

        logger.info('m=_fetch_and_save_promoted_tweets, msg=Found {} '
                    'tweets.'.format(len(prom_tweets_ids)))

        return prom_tweets_ids

    @logger(exclude='prom_tweets_ids')
    def _fetch_and_save_promoted_tweets_stats(self, account, prom_tweets_ids):
        """
        Retrieves given promoted_tweets(ads) stats (ENGAGEMENT and BILLING)

        Note: The asynchronous stats job accepts a maximum time range
        (end_time - start_time) of 90 days.
        Twitter requires one request for each placement (ALL_ON_TWITTER and
        PUBLISHER_NETWORK)

        Docs:
           Metrics: https://developer.twitter.com/en/docs/ads/analytics/overview/metrics-and-segmentation
           Active entities: https://developer.twitter.com/en/docs/ads/analytics/api-reference/active-entities
           Entity Stats: https://developer.twitter.com/en/docs/ads/analytics/api-reference/asynchronous

        :param account: account from type twitter_ads.account.Account
        :param prom_tweets_ids: list of integers with api promoted tweet ids
        :return: List of dicts with campaigns stats
        """

        # Analytics request parameters
        start_time, end_time = self._get_utc_start_and_end_datetime()
        kwargs = {
            'account': account,
            'start_time': start_time,
            'end_time': end_time,
            'granularity': GRANULARITY.DAY,
            'metric_groups': [METRIC_GROUP.ENGAGEMENT, METRIC_GROUP.BILLING],
            'segmentation_type': 'PLATFORMS'
        }

        # Twitter analytics endpoints support a maximum of 20 entity IDs per request
        batch_ids = self._split_into_chunks(prom_tweets_ids, 20)

        prom_tweets_list = []
        for _ids in batch_ids:
            logger.info('m=_fetch_and_save_promoted_tweets_stats, msg=Getting stats for'
                        ' tweets ids: {}'.format(str(_ids)))

            queued_job_1 = self._queue_async_stats_job(
                _ids=_ids,
                placement=PLACEMENT.ALL_ON_TWITTER,
                **kwargs)
            queued_job_2 = self._queue_async_stats_job(
                _ids=_ids,
                placement=PLACEMENT.PUBLISHER_NETWORK,
                **kwargs)

            job_1_result, job_2_result = self._fetch_jobs_result(account,
                                                                 queued_job_1['id'],
                                                                 queued_job_2['id'])

            all_on_twitter_stats = \
                PromotedTweet.async_stats_job_data(account, job_1_result['url'])
            publisher_network_stats = \
                PromotedTweet.async_stats_job_data(account, job_2_result['url'])

            prom_tweets_list += self._merge_placements_stats(all_on_twitter_stats,
                                                             publisher_network_stats)

            logger.info('m=_fetch_and_save_promoted_tweets_stats. msg=Now parsing and '
                        'saving data.')

        self._save_to_s3(account.id, self.S3_PROMOTED_TWEETS_STATS_FOLDER,
                         prom_tweets_list)

    @staticmethod
    def _job_has_finished(job_result):
        return 'url' in job_result and job_result['url'] is not None

    @logger
    def _fetch_jobs_result(self, account, job_1_id, job_2_id):
        """
        Wait for jobs to finish and extracts its results.
        """
        tries = 0
        job_1_result = None
        job_2_result = None
        finished_all_jobs = False

        while not finished_all_jobs:

            tries += 1
            logger.info('m=_fetch_jobs_result, msg=Checking if both jobs have completed'
                        ' try={}'.format(tries))

            # Twitter API requires some time for the job to complete
            time.sleep(self._JOB_WAIT_SECONDS)

            job_1_result = Campaign.async_stats_job_result(account, job_1_id)
            job_2_result = Campaign.async_stats_job_result(account, job_2_id)

            if self._job_has_finished(job_1_result) and self._job_has_finished(
                    job_2_result):
                finished_all_jobs = True
            elif tries == self._JOB_STATUS_MAX_TRIES:
                job_ids = ', '.join(str(x) for x in [job_1_id, job_2_id])
                spent_time = self._JOB_STATUS_MAX_TRIES * self._JOB_WAIT_SECONDS

                raise RuntimeError(
                    'm=_fetch_jobs_result, msg=Twitter API is taking too long to finish'
                    ' jobs processing., job_ids={} spent_time={}'.format(job_ids,
                                                                         spent_time))

        logger.info('m=_fetch_jobs_result, msg=Jobs have completed successfully.')

        return job_1_result, job_2_result

    @staticmethod
    @logger
    def _queue_async_stats_job(account, _ids, metric_groups, granularity,
                               placement, start_time, end_time, segmentation_type):
        return PromotedTweet.queue_async_stats_job(account, _ids, metric_groups,
                                                   granularity=granularity,
                                                   placement=placement,
                                                   segmentation_type=segmentation_type,
                                                   start_time=start_time,
                                                   end_time=end_time)

    @staticmethod
    def _add_platform_tweet_to_list(all_promoted_tweets_stats, prom_twt_id, platform_id,
                                    plat_twt):
        if prom_twt_id not in all_promoted_tweets_stats:
            all_promoted_tweets_stats.update({
                prom_twt_id: {}
            })

        if platform_id not in all_promoted_tweets_stats[prom_twt_id]:
            all_promoted_tweets_stats[prom_twt_id].update({
                platform_id: {
                    'id_ad': prom_twt_id
                }
            })

        all_promoted_tweets_stats[prom_twt_id][platform_id].update(plat_twt)
        return all_promoted_tweets_stats

    @staticmethod
    def _build_metrics_tweet_dict(plat_stats, prom_twt_id, platform_id,
                                  placement_prefix):
        plat_twt = {}
        plat_twt.update({
            'id_ad': prom_twt_id,
            'segment_value': platform_id,
            'segment_name': plat_stats['segment']['segment_name']
        })
        metrics = {
            '{}_{}'.format(placement_prefix, k): v for k, v in
            plat_stats['metrics'].items()
        }
        plat_twt.update(metrics)

        return plat_twt

    @logger(exclude=['all_on_twitter_stats', 'publisher_network_stats'])
    def _merge_placements_stats(self, all_on_twitter_stats, publisher_network_stats):
        """
        Extract platform(Ios, Android, Web) stats and merge the two placements stats
        for each platform using tweet and platform ids

        Note: the segment_name will be one of Android, Ios, etc and segment_value an id
        """

        all_promoted_tweets_stats = dict()

        for aot_prom_tweet in all_on_twitter_stats['data']:
            prom_twt_id = aot_prom_tweet['id']

            # id_data contains one object with stats by platform
            for plat_stats in aot_prom_tweet['id_data']:
                platform_id = plat_stats['segment']['segment_value']

                plat_twt = self._build_metrics_tweet_dict(plat_stats, prom_twt_id,
                                                          platform_id,
                                                          'all_on_twitter')

                all_promoted_tweets_stats = self._add_platform_tweet_to_list(
                    all_promoted_tweets_stats, prom_twt_id, platform_id, plat_twt)

        for pn_prom_tweet in publisher_network_stats['data']:
            prom_twt_id = pn_prom_tweet['id']

            for plat_stats in pn_prom_tweet['id_data']:
                platform_id = plat_stats['segment']['segment_value']

                plat_twt = self._build_metrics_tweet_dict(plat_stats, prom_twt_id,
                                                          platform_id,
                                                          'publisher_network_segment')

                all_promoted_tweets_stats = self._add_platform_tweet_to_list(
                    all_promoted_tweets_stats, prom_twt_id, platform_id, plat_twt)

        tweets_stats_list = []
        for twt_group in all_promoted_tweets_stats.values():
            tweets_stats_list += twt_group.values()

        return tweets_stats_list
