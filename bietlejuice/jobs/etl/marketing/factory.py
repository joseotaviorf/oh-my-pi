from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.marketing.criteo_campaigns import CriteoCampaigns
from bietlejuice.jobs.etl.marketing.facebook_ads import FacebookAds
from bietlejuice.jobs.etl.marketing.google_ads import GoogleAds
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum

logger = QuintoAndarLogger("MarketingFactory")


class MarketingFactory(object):

    @staticmethod
    def factory(_class, s3_bucket, execution_date, **kwargs):
        __class = MarketingFactory.__dispatch_dict(_class)
        if _class is None:
            raise Exception('m=factory, _class={}, msg=class type not found'.format(_class))

        return __class(
            s3_bucket=s3_bucket,
            account=kwargs['account'],
            execution_date=execution_date,
            auth=kwargs['auth']
        )

    @staticmethod
    @logger
    def __dispatch_dict(_class):
        return {
            MarketingEnum.GOOGLE_ADS: GoogleAds,
            MarketingEnum.FACEBOOK_ADS: FacebookAds,
            MarketingEnum.CRITEO: CriteoCampaigns
        }.get(_class)
