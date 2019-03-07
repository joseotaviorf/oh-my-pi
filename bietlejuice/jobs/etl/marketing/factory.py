from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.marketing.facebook_ads import FacebookAds
from bietlejuice.jobs.etl.marketing.google_ads import GoogleAds
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum

logger = QuintoAndarLogger("MarketingFactory")


class MarketingFactory(object):

    @staticmethod
    def factory(class_, s3_bucket, execution_date, account=None):
        __class = MarketingFactory.__dispatch_dict(class_)
        if class_ is None:
            raise TypeError('m=factory, class_={}, msg=class type not found'.format(class_))

        return __class(
            s3_bucket=s3_bucket,
            account=account,
            execution_date=execution_date
        )

    @staticmethod
    @logger
    def __dispatch_dict(class_):
        return {
            MarketingEnum.GOOGLE_ADS: GoogleAds,
            MarketingEnum.FACEBOOK_ADS: FacebookAds
        }.get(class_)
