from bietlejuice.jobs.dags.marketing.marketing_facebook_ads_subdag import MarketingFacebookAdsSubDag
from bietlejuice.jobs.dags.marketing.marketing_google_ads_subdag import MarketingGoogleAdsSubDag
from bietlejuice.jobs.new_etl.marketing.marketing_enum import MarketingEnum


class MarketingSubDagFactory(object):

    @staticmethod
    def factory(clazz, bucket, sub_dag_name, dag_name, schedule_interval, start_date, integration=None, accounts=None):
        __clazz = MarketingSubDagFactory.__dispatch_dict(clazz)
        if clazz is None:
            raise Exception('m=factory, clazz={}, msg=class type not found'.format(clazz))

        return __clazz(
            clazz=clazz,
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            accounts=accounts,
            integration=integration
        )

    @staticmethod
    def __dispatch_dict(clazz):
        return {
            MarketingEnum.GOOGLE_ADS: MarketingGoogleAdsSubDag,
            MarketingEnum.FACEBOOK_ADS: MarketingFacebookAdsSubDag
        }.get(clazz)
