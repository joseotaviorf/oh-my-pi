from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.dags.marketing.marketing_facebook_ads_subdag import MarketingFacebookAdsSubDag
from bietlejuice.jobs.dags.marketing.marketing_google_ads_subdag import MarketingGoogleAdsSubDag
from bietlejuice.jobs.new_etl.marketing.marketing_enum import MarketingEnum

logger = QuintoAndarLogger("MarketingSubDagFactory")


class MarketingSubDagFactory(object):
    @staticmethod
    @logger
    def factory(class_, bucket, sub_dag_name, dag_name, schedule_interval, start_date, integration=None, accounts=None):
        class__ = MarketingSubDagFactory.__dispatch_dict(class_)
        if class_ is None:
            raise Exception('m=factory, class_={}, msg=class type not found'.format(class_))

        return class__(
            class_=class_,
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            accounts=accounts,
            integration=integration
        )

    @staticmethod
    @logger
    def __dispatch_dict(class_):
        return {
            MarketingEnum.GOOGLE_ADS: MarketingGoogleAdsSubDag,
            MarketingEnum.FACEBOOK_ADS: MarketingFacebookAdsSubDag
        }.get(class_)
