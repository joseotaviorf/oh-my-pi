from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.marketing.criteo_campaigns import CriteoCampaigns
from bietlejuice.jobs.etl.marketing.facebook_ads import FacebookAds
from bietlejuice.jobs.etl.marketing.google_ads import GoogleAds
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum

logger = QuintoAndarLogger("MarketingFactory")


class MarketingFactory(object):

    @staticmethod
    def factory(class_, s3_bucket, execution_date, **kwargs):
        class__ = MarketingFactory.__dispatch_dict(class_)
        if class_ is None:
            raise Exception('m=factory, _class={}, msg=class type not found'.format(class_))

        return class__(
            s3_bucket=s3_bucket,
            execution_date=execution_date,
            **kwargs
        )

    @staticmethod
    @logger
    def __dispatch_dict(class_):
        return {
            MarketingEnum.GOOGLE_ADS: GoogleAds,
            MarketingEnum.FACEBOOK_ADS: FacebookAds,
            MarketingEnum.CRITEO: CriteoCampaigns
        }.get(class_)
