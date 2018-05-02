import traceback
import petl
from datetime import datetime, date, timedelta
from facebookads import FacebookAdsApi
from facebookads.adobjects.adaccount import AdAccount
from facebookads.adobjects.adsinsights import AdsInsights as Insights
from marketing_campaigns import MarketingCampaigns
from qa_python_utils.default_logger import _logger


class FacebookCampaigns(MarketingCampaigns):

    def __init__(self, config):
        # accounts
        self.supply = 'act_1260820603984552'
        self.retargeting = 'act_994644903935458'
        self.acquisition = 'act_1626589680740974'
        self.social = 'act_994734287259853'
        self.config = config

    def get_facebook_api(self):
        my_app_id = self.config['my_app_id']
        my_app_secret = self.config['my_app_secret']
        my_access_token = self.config['my_access_token']
        return FacebookAdsApi.init(my_app_id, my_app_secret, my_access_token)

    def extract_marketing_campaigns(self, dt_start):
        api = self.get_facebook_api()
        social_account = AdAccount(self.social)
        supply_account = AdAccount(self.supply)
        ret_account = AdAccount(self.retargeting)
        acq_account = AdAccount(self.acquisition)

        fields = [
            Insights.Field.campaign_name,
            Insights.Field.campaign_id,
            Insights.Field.spend,
            Insights.Field.account_name
        ]

        insights = []
        # dt_end = dt_start + timedelta(days=3)
        dt_end = dt_start
        while dt_end <= date.today():
            _logger.info('m=extract_marketing_campaigns, dt_start={}, dt_end={}'.format(dt_start, dt_end))
            params = {
                'time_range': {'since': str(dt_start), 'until': str(dt_end)},
                'time_increment': 1,
                'level': 'campaign',
                'limit': 1000,
                'filtering': [{
                    "field": "campaign.delivery_info",
                    "operator": "IN",
                    "value": ["active", "archived", "completed", "limited", "not_delivering", "not_published",
                              "pending_review", "permanently_deleted", "recently_completed", "recently_rejected",
                              "rejected", "scheduled", "inactive"]
                }]
            }

            _logger.info('m=extract_marketing_campaigns, account={}'.format('retargeting'))
            ret_campaigns = ret_account.get_insights(fields=fields, params=params)
            for c in ret_campaigns:
                if dt_start < date(2016, 3, 1):  # regra para pegar ads na conta de social somente ate dez/2016
                    try:
                        if c['campaign_name']:
                            if c['campaign_name'].startswith('Publica'):
                                c['account_name'] = 'Social'
                    except BaseException:
                        _logger.info('m=extract_marketing_campaigns, exception={}'.format(traceback.format_exc()))
                        pass
                insights.append(c)

            _logger.info('m=extract_marketing_campaigns, account={}'.format('acquisition'))
            acq_campaigns = acq_account.get_insights(fields=fields, params=params)
            for c in acq_campaigns:
                if dt_start < date(2016, 3, 1):  # regra para pegar ads na conta de social somente ate dez/2016
                    try:
                        if c['campaign_name']:
                            if c['campaign_name'].startswith('Publica'):
                                c['account_name'] = 'Social'
                    except BaseException:
                        _logger.info('m=extract_marketing_campaigns, exception={}'.format(traceback.format_exc()))
                        pass
                insights.append(c)

            _logger.info('m=extract_marketing_campaigns, account={}'.format('social'))
            campaigns_supply_in_social_account = social_account.get_insights(fields=fields, params=params)
            for c in campaigns_supply_in_social_account:
                if dt_start <= date(2016, 12, 1):  # regra para pegar ads na conta de social somente ate dez/2016
                    try:
                        if c['campaign_name']:
                            if c['campaign_name'].startswith('Trazer pro') or c['campaign_name'].startswith('Lead ads'):
                                c['account_name'] = 'Supply'
                            else:
                                if c['campaign_name'][0:8].isdigit():
                                    c['account_name'] = 'Supply'

                            insights.append(c)
                    except ValueError:
                        _logger.info('m=extract_marketing_campaigns, exception={}'.format(traceback.format_exc()))
                        pass
                else:
                    insights.append(c)

            _logger.info('m=extract_marketing_campaigns, account={}'.format('supply'))
            supply_campaigns = supply_account.get_insights(fields=fields, params=params)
            for s in supply_campaigns:
                insights.append(s)

            # dt_start = dt_start + timedelta(days=4)
            # dt_end = dt_start + timedelta(days=3)
            # if (dt_end >= date.today()) and (dt_start < date.today()):
            #     dt_end = date.today()

        table = petl.fromdicts(insights)
        table = table.rename('date_start', 'date')
        table = table.cut('campaign_name', 'date', 'campaign_id', 'spend', 'account_name')

        return list(table)
