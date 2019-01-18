from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.dags.marketing import MarketingSubDag

logger = QuintoAndarLogger('MarketingCriteoCampaignsSubDag')


class MarketingCriteoCampaignsSubDag(MarketingSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name, schedule_interval, start_date, auth, integration=None,
                 accounts=None):
        super(MarketingCriteoCampaignsSubDag, self).__init__(class_, bucket, sub_dag_name, dag_name, schedule_interval,
                                                             start_date, integration, accounts)
