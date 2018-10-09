from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.new_etl.stitch import GoogleAdsTransfer


class GoogleAdsStitchSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date, database, accounts):
        super(GoogleAdsStitchSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)
        self.integration = 'adwords'
        self.database = database
        self.accounts = accounts

    def transfer_googleads_raw_files(self, bucket, table, date_field, **kwargs):
        transfer = GoogleAdsTransfer(
            bucket=bucket,
            execution_date=kwargs['execution_date'],
            integration=self.integration,
            database=self.database,
            table=table,
            date_field=date_field,
        )
        query = transfer.build_query()
        df = transfer.fetch_data(query)
        transfer.copy_files(df)

    def build_googleads_raw_tasks(self):
        googleads_dag = self._build_local_dag()
        self.__build_data_tasks(googleads_dag),
        return googleads_dag

    def __build_data_tasks(self, dag):
        campaign_performance_report = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='googleads_transfer_campaign_performance_report',
            python_callable=self.transfer_googleads_raw_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'campaign_performance_report',
                'date_field': 'day'
            }
        )

        keywords_performance_report = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='googleads_transfer_keywords_performance_report',
            python_callable=self.transfer_googleads_raw_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'keywords_performance_report',
                'date_field': 'day'
            }
        )

        click_performance_report = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='googleads_transfer_click_performance_report',
            python_callable=self.transfer_googleads_raw_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'click_performance_report',
                'date_field': 'day'
            }
        )

        return campaign_performance_report, keywords_performance_report, click_performance_report
