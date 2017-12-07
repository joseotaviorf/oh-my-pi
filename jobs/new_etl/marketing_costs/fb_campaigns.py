import json
import os
import petl
from datetime import datetime, date, timedelta
from facebookads import FacebookAdsApi
from facebookads.adobjects.adaccount import AdAccount
from facebookads.adobjects.adsinsights import AdsInsights as Insights
from marketing_campaigns import MarketingCampaigns


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

    def extract_marketing_campaigns(self, dt):
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
        while dt <= date.today():
            params = {
                'time_range': {'since': str(dt), 'until': str(dt)},
                'level': 'campaign',
                'limit': 1000
            }

            ret_campaigns = ret_account.get_insights(fields=fields, params=params)
            for c in ret_campaigns:
                if dt < date(2016, 3, 1):  # regra para pegar ads na conta de social somente ate dez/2016
                    try:
                        if c['campaign_name']:
                            if c['campaign_name'].startswith('Publica') :
                                c['account_name'] = 'Social'
                    except:
                        pass
                insights.append(c)

            acq_campaigns = acq_account.get_insights(fields=fields, params=params)
            for c in acq_campaigns:
                if dt < date(2016, 3, 1):  # regra para pegar ads na conta de social somente ate dez/2016
                    try:
                        if c['campaign_name']:
                            if c['campaign_name'].startswith('Publica'):
                                c['account_name'] = 'Social'
                    except:
                        pass
                insights.append(c)

            campaigns_supply_in_social_account = social_account.get_insights(fields=fields, params=params)
            for c in campaigns_supply_in_social_account:
                if dt <= date(2016, 12, 1):  # regra para pegar ads na conta de social somente ate dez/2016
                    try:
                        if c['campaign_name']:
                            if c['campaign_name'].startswith('Trazer pro') or c['campaign_name'].startswith('Lead ads'):
                                c['account_name'] = 'Supply'
                            else:
                                cnv = datetime.strptime(c['campaign_name'][0:8], '%Y%m%d')
                                if cnv:
                                    c['account_name'] = 'Supply'

                            insights.append(c)
                    except:
                        pass
                else:
                    insights.append(c)

            supply_campaigns = supply_account.get_insights(fields=fields, params=params)
            for s in supply_campaigns:
                insights.append(s)

            dt = dt + timedelta(days=1)

        table = petl.fromdicts(insights)
        table = table.rename('date_start', 'date')
        table = table.cut('campaign_name', 'date', 'campaign_id', 'spend', 'account_name')

        return list(table)

