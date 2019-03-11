from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.marketing import MarketingSubDag

logger = QuintoAndarLogger('MarketingClassifiedsCostsSubDag')


class MarketingClassifiedsCostsSubDag(MarketingSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name, schedule_interval, start_date, integration=None,
                 accounts=None, auth=None):
        super(MarketingClassifiedsCostsSubDag, self).__init__(class_, bucket, sub_dag_name, dag_name, schedule_interval,
                                                              start_date, integration, auth)
        self.auth = auth
        self.dim_tables = ["dim_classified"]
        self.fact_tables = ["fact_daily_classifieds_costs"]
        self.datalake_tables = ["marketing_classifieds_costs"]

    @logger
    def build_clean_tasks(self, dag):
        BaseDAG.build_python_operator(
            dag=dag,
            task_id='{}_task'.format(self.class_.value),
            python_callable=self.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'datalake_table': 'classifieds_costs',
                'account': 'default',
                'auth': self.auth
            }
        )
