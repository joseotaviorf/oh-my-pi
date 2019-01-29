from datetime import timedelta
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.etl.marketing.factory import MarketingFactory

logger = QuintoAndarLogger('MarketingSubDag')


class MarketingSubDag(BaseSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name, schedule_interval, start_date, integration=None,
                 accounts=None):
        super(MarketingSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)
        self.class_ = class_
        self.accounts = accounts
        self.dim_tables = []
        self.fact_tables = []
        self.datalake_tables = []
        self.integration = integration

    @logger
    def transfer_files_to_clean(self, bucket, account, datalake_table, **kwargs):
        marketing_class = MarketingFactory.factory(
            _class=self.class_,
            s3_bucket=bucket,
            account=account,
            execution_date=self.__get_execution_date(kwargs['execution_date'])
        )
        getattr(marketing_class, 'move_{}_to_clean'.format(datalake_table))()

    @logger
    def transfer_to_pre_staging(self, bucket, clean_table, prod_table, **kwargs):
        marketing_class = MarketingFactory.factory(
            _class=self.class_,
            s3_bucket=bucket,
            execution_date=self.__get_execution_date(kwargs['execution_date'])
        )
        marketing_class.load_to_pre_staging(clean_table=clean_table, prod_table=prod_table,
                                            accounts=self.accounts[clean_table])

    @logger
    def transfer_to_staging(self, bucket, dw_table, **kwargs):
        marketing_class = MarketingFactory.factory(
            _class=self.class_,
            s3_bucket=bucket,
            execution_date=self.__get_execution_date(kwargs['execution_date'])
        )
        marketing_class.load_to_staging(dw_table_name=dw_table)

    @logger
    def transfer_to_dw(self, bucket, dw_table, **kwargs):
        marketing_class = MarketingFactory.factory(
            _class=self.class_,
            s3_bucket=bucket,
            execution_date=self.__get_execution_date(kwargs['execution_date'])
        )
        marketing_class.load_to_prod(table_name=dw_table)

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

    @logger
    def build_pre_staging_tasks(self, dag):
        for table in self.datalake_tables:
            BaseDAG.build_python_operator(
                dag=dag,
                task_id=table,
                python_callable=self.transfer_to_pre_staging,
                provide_context=True,
                op_kwargs={
                    'bucket': self.bucket,
                    'clean_table': table,
                    'prod_table': self.fact_tables[0]
                }
            )

    @logger
    def build_dw_tasks(self, dag):
        dw_tables = self.dim_tables + self.fact_tables
        for table in dw_tables:
            BaseDAG.build_python_operator(
                dag=dag,
                task_id=table,
                python_callable=self.transfer_to_dw,
                provide_context=True,
                op_kwargs={
                    'bucket': self.bucket,
                    'dw_table': table,
                }
            )

    @logger
    def build_staging_tasks(self, dag):
        dim_tasks = self.build_dim_tasks(dag)
        for table in self.fact_tables:
            fact_task = self.build_fact_tasks(dag, table)
            fact_task.set_upstream(dim_tasks)

    @logger
    def build_dim_tasks(self, dag):
        tasks = []
        for table in self.dim_tables:
            tasks.append(BaseDAG.build_python_operator(
                dag=dag,
                task_id=table,
                python_callable=self.transfer_to_staging,
                provide_context=True,
                op_kwargs={
                    'bucket': self.bucket,
                    'dw_table': table
                }
            ))
        return tasks

    @logger
    def build_fact_tasks(self, dag, table):
        return BaseDAG.build_python_operator(
            dag=dag,
            task_id=table,
            python_callable=self.transfer_to_staging,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'dw_table': table
            }
        )

    @logger
    def __get_execution_date(self, execution_date):
        return execution_date - timedelta(1)
