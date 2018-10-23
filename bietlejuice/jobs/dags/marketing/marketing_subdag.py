from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.new_etl.marketing.factory import MarketingFactory
from bietlejuice.jobs.new_etl.marketing.marketing import Marketing


class MarketingCleanSubDag(BaseSubDag):
    def __init__(self, clazz, bucket, sub_dag_name, dag_name, schedule_interval, start_date, tables, accounts=None):
        super(MarketingCleanSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)
        self.clazz = clazz
        self.accounts = accounts
        self.tables = tables

    def transfer_files_to_clean(self, clazz, bucket, account, table, **kwargs):
        marketing_clazz = MarketingFactory.factory(
            _class=clazz,
            s3_bucket=bucket,
            account=account,
            execution_date=kwargs['execution_date']
        )
        getattr(marketing_clazz, 'move_{}_to_clean'.format(table))()

    def transfer_to_staging(self, bucket, dw_table_name, integration, **kwargs):
        marketing = Marketing(
            s3_bucket=bucket,
            integration=integration,
            execution_date=kwargs['execution_date']
        )
        marketing.load_to_staging(table_name=dw_table_name, integration=integration)

    def build_tasks(self, task_name):
        marketing_clean_dag = self._build_local_dag()
        getattr(self, '__build_{}_tasks'.format(task_name))(marketing_clean_dag)
        # self.__build_clean_tasks(marketing_clean_dag)
        return marketing_clean_dag

    def __build_clean_tasks(self, dag):
        for account in self.accounts:
            for table in self.tables:
                BaseDAG.build_python_operator(
                    dag=dag,
                    task_id='{}-{}'.format(table, account),
                    python_callable=self.transfer_files_to_clean,
                    provide_context=True,
                    op_kwargs={
                        'clazz': self.clazz,
                        'bucket': self.bucket,
                        'table': table,
                        'account': account
                    }
                )
