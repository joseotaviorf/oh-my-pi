from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.new_etl.marketing.factory import MarketingFactory

logger = QuintoAndarLogger('MarketingSubDag')


class MarketingSubDag(BaseSubDag):
    def __init__(self, clazz, bucket, sub_dag_name, dag_name, schedule_interval, start_date, dw_tables=None,
                 integration=None,
                 accounts=None, datalake_tables=None, fact_table=None):
        super(MarketingSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)
        self.clazz = clazz
        self.accounts = accounts
        self.dw_tables = dw_tables
        self.datalake_tables = datalake_tables
        self.integration = integration
        self.fact_table = fact_table

    def transfer_files_to_clean(self, bucket, account, datalake_table, **kwargs):
        marketing_clazz = MarketingFactory.factory(
            _class=self.clazz,
            s3_bucket=bucket,
            account=account,
            execution_date=kwargs['execution_date']
        )
        getattr(marketing_clazz, 'move_{}_to_clean'.format(datalake_table))()

    def transfer_to_pre_staging(self, bucket, clean_table, prod_table, **kwargs):
        marketing_clazz = MarketingFactory.factory(
            _class=self.clazz,
            s3_bucket=bucket,
            execution_date=kwargs['execution_date']
        )
        marketing_clazz.load_to_pre_staging(clean_table=clean_table, prod_table=prod_table, accounts=self.accounts)

    def transfer_to_staging(self, bucket, dw_table, integration, **kwargs):
        marketing_clazz = MarketingFactory.factory(
            _class=self.clazz,
            s3_bucket=bucket,
            execution_date=kwargs['execution_date']
        )
        marketing_clazz._load_to_staging(dw_table_name=dw_table)

    def transfer_to_dw(self, bucket, dw_table, **kwargs):
        marketing_clazz = MarketingFactory.factory(
            _class=self.clazz,
            s3_bucket=bucket,
            execution_date=kwargs['execution_date']
        )
        marketing_clazz._load_to_prod(table_name=dw_table)

    def build_tasks(self, task_name):
        marketing_clean_dag = self._build_local_dag()
        getattr(self, 'build_{}_tasks'.format(task_name))(marketing_clean_dag)
        return marketing_clean_dag

    @logger
    def build_clean_tasks(self, dag):
        for account in self.accounts:
            for table in self.datalake_tables:
                BaseDAG.build_python_operator(
                    dag=dag,
                    task_id='{}-{}'.format(table, account),
                    python_callable=self.transfer_files_to_clean,
                    provide_context=True,
                    op_kwargs={
                        'bucket': self.bucket,
                        'datalake_table': table.split("_")[3],
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
                    'prod_table': self.fact_table
                }
            )

    @logger
    def build_staging_tasks(self, dag):

        tables_task_dict = {}

        for table in self.dw_tables:
            tables_task_dict[table] = BaseDAG.build_python_operator(
                dag=dag,
                task_id=table,
                python_callable=self.transfer_to_staging,
                provide_context=True,
                op_kwargs={
                    'bucket': self.bucket,
                    'dw_table': table,
                    'integration': self.integration
                }
            )
        tables_task_dict['dim_google_ads_keyword'] >> tables_task_dict['fact_google_ads_daily_keywords']

    @logger
    def build_dw_tasks(self, dag):
        for table in self.dw_tables:
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
