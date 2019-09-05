from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base import BaseDAG
from bietlejuice.jobs.dags.marketing import MarketingSubDag

logger = QuintoAndarLogger('MarketingLinkedInCampaignsSubDag')


class MarketingLinkedInCampaignsSubDag(MarketingSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name,
                 schedule_interval, start_date, auth, end_date=None, accounts=None,
                 extra_configs=None):
        super(MarketingLinkedInCampaignsSubDag, self).__init__(class_, bucket,
                                                               sub_dag_name,
                                                               dag_name,
                                                               schedule_interval,
                                                               start_date, end_date,
                                                               auth,
                                                               accounts, extra_configs)
        self.dim_tables = ["dim_linkedin_campaign", "dim_linkedin_ad"]
        self.fact_tables = ["fact_linkedin_daily_cost_attributions"]
        self.datalake_tables = ["linkedin_campaigns"]

    @logger
    def build_clean_tasks(self, dag):
        for table in self.datalake_tables:
            BaseDAG.build_python_operator(
                dag=dag,
                task_id='table-{}'.format(table),
                python_callable=self.transfer_files_to_clean,
                provide_context=True,
                op_kwargs={
                    'bucket': self.bucket,
                    'datalake_table': table,
                    'account': None
                }
            )
