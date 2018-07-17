from qa_python_utils.default_logger import _logger

from bietlejuice.jobs.new_etl.campaign_monitor.campaign.bounces import CampaignBounces
from bietlejuice.jobs.new_etl.campaign_monitor.campaign.clicks import CampaignClicks
from bietlejuice.jobs.new_etl.campaign_monitor.campaign.opens import CampaignOpens
from bietlejuice.jobs.new_etl.campaign_monitor.campaign.recipients import CampaignRecipients
from bietlejuice.jobs.new_etl.campaign_monitor.campaign.spams import CampaignSpams
from bietlejuice.jobs.new_etl.campaign_monitor.campaign.unsubscribes import CampaignUnsubscribes


class CampaignMonitorFactory(object):

    @staticmethod
    def factory(_class, **kwargs):
        __class = CampaignMonitorFactory.__dispatch_dict(_class)
        if _class is None:
            _logger.error('m=factory, _class={}, msg=class type not found'.format(_class))
            raise Exception

        return __class(
            bucket=kwargs['bucket'],
            cm_auth=kwargs['cm_auth'],
            _type=_class,
            execution_date=kwargs['execution_date']
        )

    @staticmethod
    def __dispatch_dict(_class):
        return {
            'bounces': CampaignBounces,
            'clicks': CampaignClicks,
            'opens': CampaignOpens,
            'recipients': CampaignRecipients,
            'spams': CampaignSpams,
            'unsubscribes': CampaignUnsubscribes
        }.get(_class)
