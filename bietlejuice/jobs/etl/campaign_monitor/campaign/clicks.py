from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.campaign_monitor.campaign.campaign_monitor import CampaignMonitorCampaign

logger = QuintoAndarLogger('CampaignClicks')


class CampaignClicks(CampaignMonitorCampaign):
    @logger(exclude='cm_auth')
    def __init__(self, s3_bucket, cm_auth, _type, execution_date):
        super(CampaignClicks, self).__init__(s3_bucket, cm_auth, _type, execution_date)

    @logger
    def request_campaign_data(self):
        self._delete_old_files()

        result_gen = self._request_incremental_campaign_data()
        self._build_objs_and_send_to_s3(
            result_gen=result_gen,
            json_fields=self.get_json_fields()
        )

    @logger
    def get_json_fields(self):
        return ['Date', 'EmailAddress', 'ListID', 'IPAddress', 'URL']
