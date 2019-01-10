import tempfile
import petl
from googleads import adwords
from datetime import datetime
from marketing_campaigns import MarketingCampaigns


class GoogleCampaigns(MarketingCampaigns):

    def __init__(self, config):
        # Initialize appropriate service.
        self.clients = []
        self.clients.append({'client': adwords.AdWordsClient.LoadFromString(
            config['sp_account']), 'account_name': 'QuintoAndar - Sao Paulo'})
        self.clients.append({'client': adwords.AdWordsClient.LoadFromString(
            config['display_account']), 'account_name': 'QuintoAndar - Display'})
        self.clients.append({'client': adwords.AdWordsClient.LoadFromString(
            config['broad_location_account']), 'account_name': 'QuintoAndar - Broad location + DSA'})
        self.clients.append({'client': adwords.AdWordsClient.LoadFromString(
            config['others_account']), 'account_name': 'QuintoAndar - Other Cities'})
        self.clients.append({'client': adwords.AdWordsClient.LoadFromString(
            config['rj_account']), 'account_name': 'QuintoAndar - Rio de Janeiro'})
        self.clients.append({'client': adwords.AdWordsClient.LoadFromString(
            config['institutional_account']), 'account_name': 'QuintoAndar - Institucional'})
        self.clients.append({'client': adwords.AdWordsClient.LoadFromString(
            config['universal_app_account']), 'account_name': 'QuintoAndar - Universal App Campaigns'})

    def extract_marketing_campaigns(self, dt):
        table = petl.fromdicts([])
        for client in self.clients:
            table = petl.cat(table, self.extract_marketing_campaigns_from_client(client, dt))
        return list(table)

    def extract_marketing_campaigns_from_client(self, client, dt):
        adwords_client = client['client']
        account_name = client['account_name']
        print account_name
        report_downloader = adwords_client.GetReportDownloader(version='v201802')
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
        table = petl.addfield(table, 'account_name', account_name)

        return table
