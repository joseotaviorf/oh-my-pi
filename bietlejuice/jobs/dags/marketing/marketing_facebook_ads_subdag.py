from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.dags.marketing import MarketingSubDag

logger = QuintoAndarLogger('MarketingFacebookAdsSubDag')


class MarketingFacebookAdsSubDag(MarketingSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name, schedule_interval, start_date, integration=None,
                 accounts=None, auth=None):
        super(MarketingFacebookAdsSubDag, self).__init__(class_, bucket, sub_dag_name, dag_name, schedule_interval,
                                                         start_date, integration, accounts)
        self.dim_tables = ["dim_facebook_ad"]
        self.fact_tables = ["fact_facebook_daily_cost_attributions"]
        self.datalake_tables = ["marketing_facebook_ads"]
