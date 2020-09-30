from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.marketing import MarketingSubDag
from bietlejuice.jobs.etl.marketing.factory import MarketingFactory
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('MarketingLifullCampaignsSubDag')


class MarketingLifullCampaignsSubDag(MarketingSubDag):
    def __init__(self, class_, bucket, sub_dag_name, dag_name,
                 schedule_interval, start_date, auth, end_date=None, integration=None,
                 accounts=None, extra_configs=None):
        super(MarketingLifullCampaignsSubDag, self).__init__(class_, bucket,
                                                             sub_dag_name,
                                                             dag_name,
                                                             schedule_interval,
                                                             start_date, auth, end_date,
                                                             accounts=accounts)
        self.dim_tables = [['dim_mitula_campaign'], ['dim_trovit_campaign']]
        self.fact_tables = [['fact_mitula_daily_cost_attributions'], ['fact_trovit_daily_cost_attributions']]
        self.datalake_tables = ['marketing_lifull_campaigns']
        self.group_names = ['trovit', 'mitula']

    @logger
    def build_raw_tasks(self, dag):
        for account in self.accounts:
            BaseDAG.build_python_operator(
                dag=dag,
                task_id='{}-{}'.format(self.class_.value, account[1]),
                python_callable=self.transfer_files_to_raw,
                provide_context=True,
                op_kwargs={
                    'bucket': self.bucket,
                    'account': account,
                    'extra_configs': self.extra_configs
                }
            )

    def _transfer_files_to_clean(self, bucket, account, datalake_table, group_name, **kwargs):
        marketing_class = MarketingFactory.factory(
            class_=self.class_,
            s3_bucket=bucket,
            execution_date=self._get_execution_date(kwargs['execution_date']),
            account=account,
            auth=self.auth,
            extra_configs=self.extra_configs
        )

        getattr(marketing_class, 'move_{}_to_clean'.format(datalake_table))(group_name)

    @logger
    def build_clean_tasks(self, dag):
        for account in self.accounts:
            for curr_group_name in self.group_names:
                BaseDAG.build_python_operator(
                    dag=dag,
                    task_id='{}_{}_{}_task'.format(self.class_.value, curr_group_name, account[1]),
                    python_callable=self._transfer_files_to_clean,
                    provide_context=True,
                    op_kwargs={
                        'bucket': self.bucket,
                        'datalake_table': self.datalake_tables[0],
                        'account': account,
                        'group_name': curr_group_name
                    }
                )

    @logger
    def build_staging_tasks(self, dag):
        if len(self.dim_tables) != len(self.fact_tables):
            raise IndexError(
                'm=build_staging_tasks, length_dim_tables={}, length_fact_tables={}, '
                'msg=Lists must have the same size'.format(len(self.dim_tables), len(self.fact_tables)))

        for index in range(len(self.dim_tables)):
            dim_tasks = self.build_dim_tasks(dag, index)
            for table in self.fact_tables[index]:
                fact_task = self.build_fact_tasks(dag, table)
                fact_task.set_upstream(dim_tasks)

    @logger
    def build_dim_tasks(self, dag, index):
        tasks = []
        for table in self.dim_tables[index]:
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
    def build_dw_tasks(self, dag):
        tables_list = self.dim_tables + self.fact_tables
        dw_tables = [val for sublist in tables_list for val in sublist]
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
