from bietlejuice.jobs.dags.marketing.marketing_lifull_campaigns_subdag import \
    MarketingLifullCampaignsSubDag
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger("MarketingSubDagFactory")


class MarketingSubDagFactory(object):
    @staticmethod
    def factory(class_, bucket, sub_dag_name, dag_name, schedule_interval,
                start_date, end_date=None, accounts=None,
                auth=None, extra_configs=None):
        logger.info(
            "m=factory, msg=creating class instance, class={}".format(class_))
        class__ = MarketingSubDagFactory.__dispatch_dict(class_)
        if class__ is None:
            raise RuntimeError(
                'm=factory, class_={}, msg=class type not found'.format(class_))

        return class__(
            class_=class_,
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            end_date=end_date,
            accounts=accounts,
            auth=auth,
            extra_configs=extra_configs
        )

    @staticmethod
    @logger
    def __dispatch_dict(class_):
        return {
            MarketingEnum.LIFULL: MarketingLifullCampaignsSubDag
        }.get(class_)
