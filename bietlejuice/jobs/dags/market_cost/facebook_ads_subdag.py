from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.new_etl.stitch.template.facebook_ads_raw_transfer import FacebookAdsTransferRaw


class FacebookAdsSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(FacebookAdsSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)
        self.integration = "facebook_ads"
        self.database = "stitch"

    def transfer_facebook_files(self, bucket, integration, database, table, date_field, account, **kwargs):
        transfer = FacebookAdsTransferRaw(
            bucket=bucket,
            execution_date=kwargs['execution_date'],
            integration=integration,
            database=database,
            table=table,
            date_field=date_field,
            account=account)
        transfer.move_facebook_files()

    def build_facebook_tasks(self):
        facebook_dag = self._build_local_dag()

        (demand_acquisition, social) = self.__build_data_tasks(facebook_dag)

        return facebook_dag

    def __build_data_tasks(self, dag):
        demand_acquisition = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='faceads_demand_acquisition_transfer',
            python_callable=self.transfer_facebook_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'campaigns',
                'date_field': 'start_time',
                'account': 'demand_acquisition'
            }
        )

        social = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='faceads_social_transfer',
            python_callable=self.transfer_facebook_files,
            provide_context=True,
            op_kwargs={
                'bucket': self.bucket,
                'table': 'campaigns',
                'date_field': 'start_time',
                'account': 'social'
            }
        )

        return demand_acquisition, social
