from datetime import datetime

from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base import BaseDAG
from bietlejuice.jobs.dags.marketing import MarketingSubDag
from bietlejuice.jobs.etl.marketing.linkedin_campaigns import LinkedInCampaigns

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
        self.dim_tables = ["dim_linkedin_campaign_group", "dim_linkedin_campaign",
                           "dim_linkedin_creative"]
        self.fact_tables = ["fact_linkedin_daily_cost_attributions"]
        self.tables = ["linkedin_campaign_groups", "linkedin_campaigns",
                       "linkedin_creatives", "linkedin_creatives_stats"]

    @logger
    def build_clean_tasks(self, dag):
        linkedin_campaigns = LinkedInCampaigns(self.bucket, datetime.now(), self.auth)
        accounts = linkedin_campaigns.get_accounts()
        logger.info(
            'm=build_clean_tasks, msg={} accounts found'.format(accounts.count))

        for account in accounts:
            for table in self.tables:
                BaseDAG.build_python_operator(
                    dag=dag,
                    task_id='acc-{}-{}-task'.format(account.id, table),
                    python_callable=self.transfer_files_to_clean,
                    provide_context=True,
                    op_kwargs={
                        'bucket': self.bucket,
                        'datalake_table': table,
                        'account': account.id
                    }
                )
