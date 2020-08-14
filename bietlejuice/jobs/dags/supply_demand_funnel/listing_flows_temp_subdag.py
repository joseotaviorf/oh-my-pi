from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.base_dag import BaseDAG
import bietlejuice.jobs.base.new_base_etl as utils

logger = QuintoAndarLogger('ListingFlowsTempSubDag')


class ListingFlowsTempSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(ListingFlowsTempSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
        )

    @logger
    def build_listing_flows(self):
        listing_flows_temp_dag = self._build_local_dag()

        ods_listing_flows_with_reprocessed_leads_task, ods_potential_listings_task, \
            dw_fact_house_listing_flows = self.__build_data_tasks(listing_flows_temp_dag)

        ods_listing_flows_with_reprocessed_leads_task >> ods_potential_listings_task >> dw_fact_house_listing_flows

        return listing_flows_temp_dag

    @logger
    def __build_data_tasks(self, dag):
        ods_listing_flows_with_reprocessed_leads_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_listing_flows_with_reprocessed_leads_temp',
            python_callable=utils.materialize_view_ods,
            op_kwargs={
                'bucket': self.bucket,
                'view_name': 'listing_flows_with_reprocessed_leads_temp'
            }
        )

        ods_potential_listings_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_potential_listings_temp',
            python_callable=utils.materialize_view_ods,
            op_kwargs={
                'bucket': self.bucket,
                'view_name': 'potential_listings_temp'
            }
        )

        dw_fact_house_listing_flows = BaseDAG.build_python_operator(
            dag=dag,
            task_id="DW_Fact_House_Listing_Flows_temp",
            python_callable=utils.load_dim_from_ods_to_dw,
            op_kwargs={
                "dim_name": "house_listing_flows_temp",
                "is_fact": True,
                "bucket": self.bucket,
                "insert_dummy": False,
            }
        )

        return ods_listing_flows_with_reprocessed_leads_task, ods_potential_listings_task, dw_fact_house_listing_flows
