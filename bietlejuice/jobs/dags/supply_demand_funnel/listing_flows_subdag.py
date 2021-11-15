from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.base_dag import BaseDAG
import bietlejuice.jobs.base.new_base_etl as utils

logger = QuintoAndarLogger('ListingFlowsSubDag')


class ListingFlowsSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(ListingFlowsSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
        )

    @logger
    def build_listing_flows(self):
        listing_flows_dag = self._build_local_dag()

        (ods_listing_flows_with_reprocessed_leads_task,
            ods_acquisitions_task,
            ods_base_photo_tasks_task,
            ods_rn_lead_task,
            ods_potential_listings_lead_tasks_task,
            ods_rep_leads_task,
            ods_potential_listings_rep_leads_task,
            ods_potential_listings_house_b2b_task,
            ods_potential_listings_task,
            ods_lead_city_region_task,
            dw_fact_house_listing_flows) = self.__build_data_tasks(listing_flows_dag)

        ods_potential_listings_lead_tasks_task.set_upstream([
            ods_base_photo_tasks_task,
            ods_rn_lead_task
        ])

        ods_rep_leads_task >> ods_potential_listings_rep_leads_task

        ods_listing_flows_with_reprocessed_leads_task.set_downstream([
            ods_acquisitions_task,
            ods_potential_listings_house_b2b_task,
            ods_potential_listings_lead_tasks_task,
            ods_potential_listings_rep_leads_task
        ])

        ods_potential_listings_task.set_upstream([
            ods_potential_listings_lead_tasks_task,
            ods_potential_listings_rep_leads_task,
            ods_potential_listings_house_b2b_task,
            ods_acquisitions_task,
            ods_listing_flows_with_reprocessed_leads_task
        ])

        dw_fact_house_listing_flows.set_upstream([ods_potential_listings_task, ods_lead_city_region_task])

        return listing_flows_dag

    @logger
    def __build_data_tasks(self, dag):
        ods_listing_flows_with_reprocessed_leads_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_listing_flows_with_reprocessed_leads',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'listing_flows_with_reprocessed_leads'
            }
        )

        ods_acquisitions_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_acquisitions',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'acquisitions'
            }
        )

        ods_base_photo_tasks_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_base_photo_tasks',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'base_photo_tasks'
            }
        )

        ods_rn_lead_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_rn_lead',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'rn_lead'
            }
        )

        ods_potential_listings_lead_tasks_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_potential_listings_lead_tasks',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'potential_listings_lead_tasks'
            }
        )

        ods_rep_leads_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_rep_leads',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'rep_leads'
            }
        )

        ods_potential_listings_rep_leads_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_potential_listings_rep_leads',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'potential_listings_rep_leads'
            }
        )

        ods_potential_listings_house_b2b_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_potential_listings_house_b2b',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'potential_listings_house_b2b'
            }
        )

        ods_potential_listings_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_potential_listings',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'potential_listings'
            }
        )

        ods_lead_city_region_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_lead_city_region',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'lead_city_region'
            }
        )

        dw_fact_house_listing_flows = BaseDAG.build_python_operator(
            dag=dag,
            task_id="DW_Fact_House_Listing_Flows",
            python_callable=utils.load_dim_from_ods_to_dw,
            op_kwargs={
                "dim_name": "house_listing_flows",
                "is_fact": True,
                "bucket": self.bucket,
                "insert_dummy": False,
            }
        )

        return (
            ods_listing_flows_with_reprocessed_leads_task,
            ods_acquisitions_task,
            ods_base_photo_tasks_task,
            ods_rn_lead_task,
            ods_potential_listings_lead_tasks_task,
            ods_rep_leads_task,
            ods_potential_listings_rep_leads_task,
            ods_potential_listings_house_b2b_task,
            ods_potential_listings_task,
            ods_lead_city_region_task,
            dw_fact_house_listing_flows
        )
