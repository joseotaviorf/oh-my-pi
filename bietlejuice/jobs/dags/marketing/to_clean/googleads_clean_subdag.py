from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.new_etl.marketing import GoogleAdsClean


class GoogleAdsCleanSubDag(BaseSubDag):
    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date, accounts):
        super(GoogleAdsCleanSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)
        self.accounts = accounts

    def transfer_googleads_clean_files(self, bucket, table, accounts, **kwargs):
        transfer = GoogleAdsClean(
            s3_bucket=bucket,
            table=table,
            accounts=accounts,
            execution_date=kwargs['execution_date']
        )
        transfer.run()

    def build_googleads_clean_tasks(self):
        googleads_clean_dag = self._build_local_dag()
        self.__build_clean_tasks(googleads_clean_dag)
        return googleads_clean_dag

    def __build_clean_tasks(self, dag):
        keywords_clean = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='googleads_clean_keywords_performance_report',
            python_callable=self.transfer_googleads_clean_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'keyword',
                'accounts': self.accounts
            }
        )

        campaigns_clean = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='googleads_clean_campaigns_performance_report',
            python_callable=self.transfer_googleads_clean_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'campaign',
                'accounts': self.accounts
            }
        )

        return keywords_clean, campaigns_clean
