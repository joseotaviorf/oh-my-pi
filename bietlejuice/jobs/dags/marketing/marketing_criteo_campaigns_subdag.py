from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.marketing import MarketingSubDag

logger = QuintoAndarLogger('MarketingCriteoCampaignsSubDag')


class MarketingCriteoCampaignsSubDag(MarketingSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name, schedule_interval, start_date, auth, integration=None,
                 accounts=None):
        super(MarketingCriteoCampaignsSubDag, self).__init__(class_, bucket, sub_dag_name, dag_name, schedule_interval,
                                                             start_date, auth, integration)
        self.dim_tables = ["dim_criteo_campaign"]
        self.fact_tables = ["fact_criteo_daily_cost_attributions"]
        self.datalake_tables = ["marketing_criteo_campaigns"]

    @logger
    def build_clean_tasks(self, dag):
        BaseDAG.build_python_operator(
            dag=dag,
            task_id='{}_task'.format(self.class_.value),
            python_callable=self.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'datalake_table': 'criteo_campaigns',
                'account': 'default'
            }
        )
