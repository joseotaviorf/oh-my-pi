from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.dags.marketing import MarketingSubDag

logger = QuintoAndarLogger('MarketingSubDag')


class MarketingGoogleAdsSubDag(MarketingSubDag):
    @logger
    def __init__(self, class_, bucket, sub_dag_name, dag_name, schedule_interval, start_date, integration=None,
                 accounts=None):
        super(MarketingGoogleAdsSubDag, self).__init__(class_, bucket, sub_dag_name, dag_name, schedule_interval,
                                                       start_date, integration, accounts)
        self.dim_tables = ["dim_google_keyword", "dim_google_ad"]
        self.fact_tables = ["fact_google_ads_daily_cost_attributions"]
        self.datalake_tables = ["marketing_google_keywords", "marketing_google_ads"]
