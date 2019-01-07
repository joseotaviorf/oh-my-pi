from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.etl.zendesk import ZendeskETL

logger = QuintoAndarLogger('ZendeskSubDag')


class ZendeskSubDag(BaseSubDag):
    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date, tables):
        super(ZendeskSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)
        self.zendesk_tables = tables

    @logger
    def build_tasks(self, task_name):
        zendesk_dag = self._build_local_dag()
        getattr(self, 'build_{}_tasks'.format(task_name))(zendesk_dag)
        return zendesk_dag

    @logger
    def build_clean_tasks(self, dag):
        for table in self.zendesk_tables:
            BaseDAG.build_python_operator(
                dag=dag,
                task_id=table,
                python_callable=self.__to_clean,
                provide_context=True,
                op_kwargs={
                    'table_name': table
                }
            )

    @logger(exclude='kwargs')
    def __to_clean(self, table_name, **kwargs):
        zendesk_etl = ZendeskETL(
            bucket=self.bucket,
            execution_date=kwargs['execution_date']
        )
        getattr(zendesk_etl, table_name)(table_name)
