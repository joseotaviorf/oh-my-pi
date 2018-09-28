from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.new_etl.stitch.template.facebook_ads_raw_transfer import FacebookAdsTransferRaw


class FacebookAdsSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date, database, accounts):
        super(FacebookAdsSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)
        self.integration = "facebook_ads"
        self.database = database
        self.accounts = accounts

    def transfer_facebook_files(self, bucket, table, date_field, **kwargs):
        transfer = FacebookAdsTransferRaw(
            bucket=bucket,
            execution_date=kwargs['execution_date'],
            integration=self.integration,
            database=self.database,
            table=table,
            date_field=date_field,
            accounts=self.accounts)
        transfer.execute()

    def build_facebook_tasks(self):
        facebook_dag = self._build_local_dag()
        self.__build_data_tasks(facebook_dag)
        return facebook_dag

    def __build_data_tasks(self, dag):
        campaigns = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='facebook_ads_transfer_campaigns',
            python_callable=self.transfer_facebook_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'campaigns',
                'date_field': 'start_time'
            }
        )

        ads = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='facebook_ads_transfer_ads',
            python_callable=self.transfer_facebook_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'ads',
                'date_field': 'start_time'
            }
        )

        ads_insights = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='facebook_ads_transfer_ads_insights',
            python_callable=self.transfer_facebook_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'ads_insights',
                'date_field': 'start_time'
            }
        )

        ads_insights_platform_and_device = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='facebook_ads_transfer_ads_insights_platform_and_device',
            python_callable=self.transfer_facebook_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'ads_insights_platform_and_device',
                'date_field': 'start_time'
            }
        )

        adsets = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='facebook_ads_transfer_adsets',
            python_callable=self.transfer_facebook_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'adsets',
                'date_field': 'start_time'
            }
        )

        return ads, campaigns, ads_insights, ads_insights_platform_and_device, adsets
