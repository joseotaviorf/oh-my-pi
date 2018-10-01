from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.new_etl.stitch import AdWordsTransfer


class AdWordsSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date, database):
        super(AdWordsSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)
        self.integration = 'adwords'
        self.database = database

    def transfer_adwords_files(self, bucket, table, date_field, **kwargs):
        transfer = AdWordsTransfer(
            bucket=bucket,
            execution_date=kwargs['execution_date'],
            integration=self.integration,
            database=self.database,
            table=table,
            date_field=date_field,
            source_key="raw/marketing/{integration}/{table}/acc={account}/dt={date_partition}/{file_name}.jsonl"
        )
        query = transfer.build_query()
        df = transfer.fetch_data(query)
        transfer.copy_files(df)

    def build_adwords_tasks(self):
        adwords_dag = self._build_local_dag()
        self.__build_data_tasks(adwords_dag),
        return adwords_dag

    def __build_data_tasks(self, dag):
        campaign_performance_report = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='adwords_transfer_campaign_performance_report',
            python_callable=self.transfer_adwords_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'campaign_performance_report',
                'date_field': 'startdate'
            }
        )

        keywords_performance_report = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='adwords_transfer_keywords_performance_report',
            python_callable=self.transfer_adwords_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'keywords_performance_report',
                'date_field': 'startdate'
            }
        )

        click_performance_report = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='adwords_transfer_click_performance_report',
            python_callable=self.transfer_adwords_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'click_performance_report',
                'date_field': 'startdate'
            }
        )

        return campaign_performance_report, keywords_performance_report, click_performance_report
