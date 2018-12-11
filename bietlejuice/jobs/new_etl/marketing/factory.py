from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.new_etl.marketing.facebook_ads import FacebookAds
from bietlejuice.jobs.new_etl.marketing.google_ads import GoogleAds
from bietlejuice.jobs.new_etl.marketing.marketing_enum import MarketingEnum

logger = QuintoAndarLogger("MarketingFactory")


class MarketingFactory(object):

    @staticmethod
    def factory(_class, s3_bucket, execution_date, account=None):
        __class = MarketingFactory.__dispatch_dict(_class)
        if _class is None:
            raise Exception('m=factory, _class={}, msg=class type not found'.format(_class))

        return __class(
            s3_bucket=s3_bucket,
            account=account,
            execution_date=execution_date
        )

    @staticmethod
    @logger
    def __dispatch_dict(_class):
        return {
            MarketingEnum.GOOGLE_ADS: GoogleAds,
            MarketingEnum.FACEBOOK_ADS: FacebookAds
        }.get(_class)
