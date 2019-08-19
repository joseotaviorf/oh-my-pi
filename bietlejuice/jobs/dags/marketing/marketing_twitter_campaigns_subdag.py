from datetime import datetime

from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.marketing import MarketingSubDag
from bietlejuice.jobs.etl.marketing.twitter_campaigns import TwitterCampaigns

logger = QuintoAndarLogger('MarketingTwitterCampaignsSubDag')


class MarketingTwitterCampaignsSubDag(MarketingSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name,
                 schedule_interval, start_date, auth, end_date=None, accounts=None,
                 extra_configs=None):
        super(MarketingTwitterCampaignsSubDag, self).__init__(class_, bucket,
                                                              sub_dag_name,
                                                              dag_name,
                                                              schedule_interval,
                                                              start_date, end_date,
                                                              auth,
                                                              accounts, extra_configs)

        self.dim_tables = [
            "dim_twitter_campaign",
            "dim_twitter_ad_group",
            "dim_twitter_ad"
        ]
        self.fact_tables = ["fact_twitter_daily_cost_attributions"]
        self.tables = [TwitterCampaigns.CAMPAIGNS_TABLE_NAME,
                       TwitterCampaigns.AD_GROUPS_TABLE_NAME,
                       TwitterCampaigns.ADS_TABLE_NAME,
                       TwitterCampaigns.ADS_STATS_TABLE_NAME]

    @logger
    def build_clean_tasks(self, dag):
        twitter_campaigns = TwitterCampaigns(self.bucket, datetime.now(), self.auth)
        accounts = twitter_campaigns.get_accounts()
        logger.info(
            'm=build_clean_tasks, msg={} accounts found'.format(accounts.fetched))

        for account in accounts:
            for table in self.tables:
                BaseDAG.build_python_operator(
                    dag=dag,
                    task_id='{}_task'.format(table),
                    python_callable=self.transfer_files_to_clean,
                    provide_context=True,
                    op_kwargs={
                        'bucket': self.bucket,
                        'datalake_table': table,
                        'account': account.id
                    }
                )
