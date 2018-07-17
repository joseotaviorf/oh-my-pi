from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.campaign_monitor.campaign.campaign_monitor import CampaignMonitorCampaign


class CampaignSpams(CampaignMonitorCampaign):
    @logger(exclude='cm_auth')
    def __init__(self, s3_bucket, cm_auth, _type, execution_date):
        super(CampaignSpams, self).__init__(s3_bucket, cm_auth, _type, execution_date)

    @logger
    def request_campaign_data(self):
        self.request_incremental_campaign_data()
