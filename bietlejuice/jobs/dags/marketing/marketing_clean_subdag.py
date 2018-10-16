from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.new_etl.marketing import GoogleAds


class GoogleAdsSubDag(BaseSubDag):
    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date, accounts, tables):
        super(GoogleAdsSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)
        self.accounts = accounts
        self.tables = tables

    def transfer_files_to_clean(self, bucket, account, table, **kwargs):

            transfer = GoogleAds(
                s3_bucket=bucket,
                account=account,
                execution_date=kwargs['execution_date']
            )
            getattr(transfer, table)()

    def build_clean_tasks(self):
        google_ads_clean_dag = self._build_local_dag()
        self.__build_tasks(google_ads_clean_dag)
        return google_ads_clean_dag

    def __build_tasks(self, dag):
        for account in self.accounts:
            for table in self.tables:
                BaseDAG.build_python_operator(
                    dag=dag,
                    task_id=account,
                    python_callable=self.transfer_files_to_clean,
                    provide_context=True,
                    op_kwargs={
                        'bucket': self.bucket,
                        'table': table,
                        'accounts': account
                    }
                )
