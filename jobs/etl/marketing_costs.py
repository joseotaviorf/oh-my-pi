# -*- coding: latin-1\ -*-
import os
import sys
import petl
import json
from datetime import datetime, date, timedelta
from jobs.base.base_etl import BaseETL, EnumDb
from facebookads import FacebookAdsApi
from facebookads.objects import AdAccount, Insights
from googleads import adwords
import tempfile

#accounts
supply = 'act_1260820603984552'
aquisition = 'act_994644903935458'
liquidity = aquisition
social = 'act_994734287259853'


def get_facebook_api():
    token_file = json.loads(os.environ['FACEBOOK_KEY'])
    my_app_id = token_file['my_app_id']
    my_app_secret = token_file['my_app_secret']
    my_access_token = token_file['my_access_token']
    return FacebookAdsApi.init(my_app_id, my_app_secret, my_access_token)


def extract_facebook_marketing_campaigns(dt):
    api = get_facebook_api()
    social_account = AdAccount(social)
    supply_account = AdAccount(supply)
    liq_account = AdAccount(liquidity)

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

        liq_campaigns = liq_account.get_insights(fields=fields, params=params)
        for c in liq_campaigns:
            if dt < date(2016, 3, 1):  # regra para pegar ads na conta de social somente ate dez/2016
                try:
                    if c['campaign_name']:
                        if c['campaign_name'].startswith('Publica') :
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
    table = table.cut('date', 'campaign_id', 'campaign_name', 'spend', 'account_name')

    return list(table)


def extract_google_marketing_campaigns(dt, config_string):
    # Initialize appropriate service.
    client = adwords.AdWordsClient.LoadFromString(config_string)
    report_downloader = client.GetReportDownloader(version='v201609')

    # Create report query.
    report_query = (
        """
        select
            CampaignId,
            CampaignName,
            Device,
            StartDate,
            Date,
            Impressions,
            Clicks,
            Cost
        from
            CAMPAIGN_PERFORMANCE_REPORT
        during
            {},{}
        """.format(
            dt.strftime('%Y%m%d'),
            datetime.today().strftime('%Y%m%d')
        )
    )

    report = report_downloader.DownloadReportAsStringWithAwql(
        report_query,
        'CSV',
        skip_report_header=True,
        skip_report_summary=True)

    cur, temp_file = tempfile.mkstemp()
    with open(temp_file, mode='w') as csvfile:
        csvfile.write(report.encode('utf8'))

    table = petl.fromcsv(source=temp_file, encoding='utf8')
    table = table.rename({'Campaign ID': 'campaign_id', 'Start date': 'start_date'})
    table = table.setheader(tuple(h.lower() for h in table.header()))

    # campaign areas
    supply_campaigns = [
        'lp_proprietarios',
        'lp_quanto_cobrar',
        'proprietarios_ - _android_ - _app_installs',
        'proprietarios_ - _ios_ - _app_installs'
    ]
    table = petl.addfield(
        table,
        'campaign_area',
        lambda r: 'supply' if r['campaign'] in supply_campaigns else 'liquidity'
    )

    return list(table)


if __name__ == '__main__':
    args = sys.argv
    bucket_datalake = os.environ['bi-datalake-s3-bucket']
    if len(args) > 1:
        if args[1] == 'fb':
            facebook_table = extract_facebook_marketing_campaigns(date(2016, 1, 1))
            process_name = 'facebook_ads_campaigns'

            BaseETL.bulk_insert(
                table=facebook_table,
                table_name=process_name,
                db_enum=EnumDb.BI_ODS,
                encoding='UTF8',
                append=False,
                commit=True,
                bucket_name='{}/raw/ebdb/{}'.format(bucket_datalake, process_name)
            )
            BaseETL.copy_file_between_s3_buckets(
                bucket_source=bucket_datalake,
                bucket_destination=bucket_datalake,
                full_filename_source='raw/ebdb/{0}/{0}.csv'.format(process_name),
                full_filename_dest='clean/ebdb/{0}/{0}.csv'.format(process_name)
            )

        if args[1] == 'google':
            config_key = os.environ['ADWORDS_KEY']
            ga_table = extract_google_marketing_campaigns(date(2016, 1, 1), config_key)
            process_name = 'google_ads_campaigns'

            BaseETL.bulk_insert(
                table=ga_table,
                table_name=process_name,
                db_enum=EnumDb.BI_ODS,
                encoding='UTF8',
                append=False,
                commit=True,
                bucket_name='{}/raw/ebdb/{}'.format(bucket_datalake, process_name)
            )
            BaseETL.copy_file_between_s3_buckets(
                bucket_source=bucket_datalake,
                bucket_destination=bucket_datalake,
                full_filename_source='raw/ebdb/{0}/{0}.csv'.format(process_name),
                full_filename_dest='clean/ebdb/{0}/{0}.csv'.format(process_name)
            )
