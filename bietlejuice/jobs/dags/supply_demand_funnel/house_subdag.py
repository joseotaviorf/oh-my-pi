from datetime import datetime

from qa_python_utils.default_logger import logger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag


class HouseSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(HouseSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='imovel',
            ods_stg_table_name='property'
        )

    @logger
    def build_house_with_tests(self):
        house_dag = self._build_local_dag()

        (property_task, affiliate, rent_flow, listing_views, property_listing, staging_dim_property_task, dim_property,
         dim_status_over_period) = self.__build_data_tasks(house_dag)

        tests_tasks = self.build_tests_tasks(house_dag)

        affiliate >> property_task
        staging_dim_property_task.set_upstream([rent_flow, property_listing, property_task])
        staging_dim_property_task.set_downstream(tests_tasks)
        dim_property.set_upstream(tests_tasks)
        dim_property >> dim_status_over_period

        return house_dag

    @logger
    def __build_data_tasks(self, dag):
        property_task = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='ODS_imovel',
            func_command=utils.extract_query_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'property',
                'command': 'call ebdb.list_imovel();',
                'table_name': 'imovel',
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        affiliate = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='ODS_affiliate_payments',
            func_command=utils.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'affiliate_payments',
                'file_name': 'affiliate_payments.sql',
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        rent_flow = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_rent_flow',
            dag=dag,
            func_command=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'rental_flow',
                'table_name': 'FluxoLocacao',
                'copy_to_clean': False,
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        listing_views = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_listing_views',
            dag=dag,
            func_command=utils.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'listing_views',
                'file_name': 'listing_views.sql',
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        property_listing = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='ODS_property_listing',
            func_command=utils.materialize_view_ods,
            op_kwargs={
                'view_name': 'property_listing'
            }
        )

        staging_dim_property_task = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='STAGING_dim_property',
            func_command=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'property',
                'post_command': "update staging.dim_property set dt_timestamp = '{}' where sk_property = -1;".format(
                    datetime.now().strftime('%Y-%m-%d'))
            }
        )

        dim_property = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='DW_dim_property',
            func_command=utils.load_dim_from_staging_to_dw,
            op_kwargs={
                'dim_name': 'property'
            }
        )

        dim_status_over_period = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='DW_dim_property_status_over',
            func_command=utils.load_dim_from_ods_to_dw,
            op_kwargs={
                'dim_name': 'property_status_over_period',
                'insert_dummy': False
            }
        )

        return (property_task, affiliate, rent_flow, listing_views, property_listing, staging_dim_property_task,
                dim_property, dim_status_over_period)
