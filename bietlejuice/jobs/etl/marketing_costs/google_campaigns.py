import tempfile
import petl
from googleads import adwords
from datetime import datetime


class GoogleCampaigns(object):

    def __init__(self, config_string):
        # Initialize appropriate service.
        self.client = adwords.AdWordsClient.LoadFromString(config_string)
        self.report_downloader = self.client.GetReportDownloader(version='v201708')

    def extract_google_marketing_campaigns(self, dt):
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

        report = self.report_downloader.DownloadReportAsStringWithAwql(
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
