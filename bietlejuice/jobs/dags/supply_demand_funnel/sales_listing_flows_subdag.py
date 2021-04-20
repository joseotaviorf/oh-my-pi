from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.base_dag import BaseDAG
import bietlejuice.jobs.base.new_base_etl as utils

logger = QuintoAndarLogger('SalesListingFlowsSubDag')


class SalesListingFlowsSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(SalesListingFlowsSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
        )

    @logger
    def build_sales_listing_flows(self):
        sales_listing_flows_dag = self._build_local_dag()

        (ods_sales_listing_flows_with_reprocessed_leads_task,
            ods_sales_acquisitions_task,
            ods_sales_base_photo_tasks_task,
            ods_sales_leads_b2b_task,
            ods_sales_rep_leads_task,
            ods_sales_rn_lead_task,
            ods_sales_potential_listings_task,
            dw_sale_fact_listing_flows) = self.__build_data_tasks(sales_listing_flows_dag)

        ods_sales_listing_flows_with_reprocessed_leads_task >> ods_sales_acquisitions_task

        ods_sales_potential_listings_task.set_upstream([
            ods_sales_acquisitions_task,
            ods_sales_base_photo_tasks_task,
            ods_sales_leads_b2b_task,
            ods_sales_rep_leads_task,
            ods_sales_rn_lead_task
        ])

        ods_sales_potential_listings_task >> dw_sale_fact_listing_flows

        return sales_listing_flows_dag

    @logger
    def __build_data_tasks(self, dag):
        ods_sales_listing_flows_with_reprocessed_leads_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_sales_listing_flows_with_reprocessed_leads',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'sales_listing_flows_with_reprocessed_leads'
            }
        )

        ods_sales_acquisitions_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_sales_acquisitions',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'sales_acquisitions'
            }
        )

        ods_sales_base_photo_tasks_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_sales_base_photo_tasks',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'sales_base_photo_tasks'
            }
        )

        ods_sales_leads_b2b_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_sales_leads_b2b',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'sales_leads_b2b'
            }
        )

        ods_sales_rep_leads_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_sales_rep_leads',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'sales_rep_leads'
            }
        )

        ods_sales_rn_lead_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_sales_rn_lead',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'sales_rn_lead'
            }
        )

        ods_sales_potential_listings_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_sales_potential_listings',
            python_callable=utils.insert_into_table_from_view_ods,
            op_kwargs={
                'view_name': 'sales_potential_listings'
            }
        )

        dw_sale_fact_listing_flows = BaseDAG.build_python_operator(
            dag=dag,
            task_id="DW_Sale_Fact_Listing_Flows",
            python_callable=utils.load_dim_from_ods_to_dw,
            op_kwargs={
                "dim_name": "listing_flows",
                "is_fact": True,
                "bucket": self.bucket,
                "insert_dummy": False,
                "schema_source": "sale",
                "schema_dest": "sale",
            }
        )

        return (
            ods_sales_listing_flows_with_reprocessed_leads_task,
            ods_sales_acquisitions_task,
            ods_sales_base_photo_tasks_task,
            ods_sales_leads_b2b_task,
            ods_sales_rep_leads_task,
            ods_sales_rn_lead_task,
            ods_sales_potential_listings_task,
            dw_sale_fact_listing_flows
        )
