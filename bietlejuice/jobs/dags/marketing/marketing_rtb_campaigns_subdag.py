from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.marketing import MarketingSubDag

logger = QuintoAndarLogger('MarketingRtbCampaignsSubDag')


class MarketingRtbCampaignsSubDag(MarketingSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name, schedule_interval, start_date, auth, integration=None,
                 accounts=None):
        super(MarketingRtbCampaignsSubDag, self).__init__(class_, bucket, sub_dag_name, dag_name, schedule_interval,
                                                          start_date, auth, integration)

    @logger
    def build_clean_tasks(self, dag):
        BaseDAG.build_python_operator(
            dag=dag,
            task_id='{}_task'.format(self.class_.value),
            python_callable=self.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'datalake_table': 'rtb_campaigns',
                'account': 'default'
            }
        )
