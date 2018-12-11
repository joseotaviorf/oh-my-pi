from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.marketing import MarketingSubDag

logger = QuintoAndarLogger('MarketingGoogleAdsSubDag')


class MarketingGoogleAdsSubDag(MarketingSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name, schedule_interval, start_date, integration=None,
                 accounts=None):
        super(MarketingGoogleAdsSubDag, self).__init__(class_, bucket, sub_dag_name, dag_name, schedule_interval,
                                                       start_date, integration, accounts)
        self.dim_tables = ["dim_google_keyword", "dim_google_ad", "dim_google_campaign"]
        self.fact_tables = ["fact_google_daily_cost_attributions"]
        self.datalake_tables = ["marketing_google_keywords", "marketing_google_ads", "marketing_google_campaigns"]

    @logger
    def build_tasks(self, task_name):
        marketing_clean_dag = self._build_local_dag()
        getattr(self, 'build_{}_tasks'.format(task_name))(marketing_clean_dag)
        return marketing_clean_dag

    @logger
    def build_clean_tasks(self, dag):
        for table in self.datalake_tables:
            for account in self.accounts[table]:
                BaseDAG.build_python_operator(
                    dag=dag,
                    task_id='{}-{}'.format(table, account),
                    python_callable=self.transfer_files_to_clean,
                    provide_context=True,
                    op_kwargs={
                        'bucket': self.bucket,
                        'datalake_table': table.split("_")[2],
                        'account': account
                    }
                )
