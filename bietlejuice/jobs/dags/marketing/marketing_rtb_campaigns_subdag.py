from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.marketing import MarketingSubDag
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.marketing import RtbCampaigns

logger = QuintoAndarLogger('MarketingRtbCampaignsSubDag')


class MarketingRtbCampaignsSubDag(MarketingSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name, schedule_interval,
                 start_date, auth, end_date=None,
                 integration=None,
                 accounts=None, extra_configs=None):
        super(MarketingRtbCampaignsSubDag, self).__init__(class_, bucket, sub_dag_name,
                                                          dag_name, schedule_interval,
                                                          start_date, end_date, auth,
                                                          integration)
        self.dim_tables = ["dim_rtb_sub_campaign"]
        self.fact_tables = ["fact_rtb_daily_cost_attributions"]
        self.tables = [RtbCampaigns.STATS_TABLE_NAME]

    @logger
    def build_clean_tasks(self, dag):
        rtb_campaigns = RtbCampaigns(self.bucket, datetime.now(), self.auth)
        accounts = rtb_campaigns.get_accounts()
        logger.info(
            'm=build_clean_tasks, msg={} accounts found'.format(len(accounts)))

        for account in accounts:
            for table in self.tables:
                BaseDAG.build_python_operator(
                    dag=dag,
                    task_id='{}_{}_task'.format(account['name'], table),
                    python_callable=self.transfer_files_to_clean,
                    provide_context=True,
                    op_kwargs={
                        'bucket': self.bucket,
                        'datalake_table': table,
                        'account': account['hash']
                    }
                )
