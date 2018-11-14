from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.dags.marketing import MarketingSubDag

logger = QuintoAndarLogger('MarketingSubDag')


class MarketingFacebookAdsSubDag(MarketingSubDag):
    def __init__(self, clazz, bucket, sub_dag_name, dag_name, schedule_interval, start_date, integration=None,
                 accounts=None):
        super(MarketingFacebookAdsSubDag, self).__init__(clazz, bucket, sub_dag_name, dag_name, schedule_interval,
                                                         start_date, integration, accounts)
        self.dim_tables = ["dim_facebook_ads_ads_insights"]
        self.fact_tables = ["fact_facebook_ads_daily_cost_attribution"]
        self.datalake_tables = ["marketing_facebook_ads_ads_insights"]
