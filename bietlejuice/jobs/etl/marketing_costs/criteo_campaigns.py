import petl
import pycriteo
import json
import os
from urllib import urlopen
from xml.etree import ElementTree
from datetime import date, timedelta


class CriteoCampaigns(object):

    def __init__(self):
        criteo_config = json.loads(os.environ['criteo'])
        user = criteo_config['user']
        pwd = criteo_config['pwd']
        token = criteo_config['token']
        self.client = pycriteo.Client(user, pwd, token)
        # 90 is Criteo upper limit
        self.MAX_DELTA = 90 - 1

    def parse_report_job(self, job_id):
        campaign_list = list()

        while True:
            if not self.client.getJobStatus(job_id) == 'Pending':
                break

        table = ElementTree.parse(
            urlopen(self.client.getReportDownloadUrl(job_id))
        ).getroot().getchildren()[0]

        rows = [i for i in table if i.tag == 'rows'][0]
        for row in rows:
            campaign_list.append(row.attrib)
        print len(campaign_list)
        return campaign_list

    def extract_criteo_marketing_campaigns(self, dt):
        # Parsing MAX_DELTA campaign days at a time from today down to provided dt
        table = []
        campaigns = self.client.getCampaigns({})
        end_date = date.today()

        while end_date > dt:
            start_date = end_date - timedelta(days=self.MAX_DELTA)
            if start_date < dt:
                start_date = dt
            job = self.client.scheduleReportJob(
                {'reportType': 'Campaign',
                 'reportSelector': {
                     'CampaignIDs': [i.campaignID for i in campaigns.campaign]},
                 'startDate': '{}'.format(start_date.strftime('%Y-%m-%d')),
                 'endDate': '{}'.format(end_date.strftime('%Y-%m-%d')),
                 'isResultGzipped': False,
                 'selectedColumns': ['ctr'],
                 'aggregationType': 'Daily'
                 }
            )
            table = table + self.parse_report_job(job.jobID)
            end_date = start_date
        table = petl.fromdicts(table)
        return list(table)