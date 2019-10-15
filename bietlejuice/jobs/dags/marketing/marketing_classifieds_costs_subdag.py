from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.marketing import MarketingSubDag
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('MarketingClassifiedsCostsSubDag')


class MarketingClassifiedsCostsSubDag(MarketingSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name, schedule_interval,
                 start_date, end_date=None, accounts=None, auth=None,
                 extra_configs=None):
        super(MarketingClassifiedsCostsSubDag, self).__init__(class_, bucket,
                                                              sub_dag_name, dag_name,
                                                              schedule_interval,
                                                              start_date, end_date,
                                                              auth, accounts,
                                                              extra_configs)
        self.dim_tables = ["dim_classified"]
        self.fact_tables = ["fact_classified_daily_cost_attributions"]

    @logger
    def build_clean_tasks(self, dag):
        BaseDAG.build_python_operator(
            dag=dag,
            task_id='{}_{}_task'.format(self.class_.value,
                                        self.extra_configs.get('side')),
            python_callable=self.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'datalake_table': "classifieds_{}_costs".format(
                    self.extra_configs.get('side')),
                'account': 'default'
            }
        )
