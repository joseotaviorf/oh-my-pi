from datetime import timedelta

from bietlejuice.jobs.etl.marketing.facebook_ads import FacebookAds
from bietlejuice.jobs.etl.marketing.google_ads import GoogleAds
from bietlejuice.jobs.etl.marketing.lifull_campaigns import LifullCampaigns
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum
from bietlejuice.jobs.etl.marketing.twitter_campaigns import TwitterCampaigns
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger("MarketingFactory")


class MarketingFactory(object):

    @staticmethod
    def factory(class_, s3_bucket, execution_date, auth=None, account=None,
                extra_configs=None):
        class__ = MarketingFactory.__dispatch_dict(class_)

        if class__ is None:
            raise TypeError(
                'm=factory, _class={}, msg=class type not found'.format(class_))

        if extra_configs and 'days_offset' in extra_configs and \
                extra_configs['days_offset'] is not None:
            execution_date = MarketingFactory._apply_offset_on_date(
                execution_date, extra_configs['days_offset'])

        return class__(
            s3_bucket=s3_bucket,
            execution_date=execution_date,
            account=account,
            auth=auth,
            extra_configs=extra_configs
        )

    @staticmethod
    @logger
    def __dispatch_dict(class_):
        return {
            MarketingEnum.GOOGLE_ADS: GoogleAds,
            MarketingEnum.FACEBOOK_ADS: FacebookAds,
            MarketingEnum.TWITTER: TwitterCampaigns,
            MarketingEnum.LIFULL: LifullCampaigns
        }.get(class_)

    @staticmethod
    def _apply_offset_on_date(date, days_offset):
        return date - timedelta(days=days_offset)
