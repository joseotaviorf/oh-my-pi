from qa_python_utils import QuintoAndarLogger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag

logger = QuintoAndarLogger('HouseSubDag')


class HouseSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(HouseSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='Imovel',
            ods_stg_table_name='property'
        )

    @logger
    def build_house_with_tests(self):
        house_dag = self._build_local_dag()

        (property_task, affiliate, rent_flow, listing_views, property_listing, staging_dim_house_listing_task, dim_house_listing,
         dim_status_over_period) = self.__build_data_tasks(house_dag)

        tests_tasks = self.build_tests_tasks(house_dag)

        affiliate >> property_task
        staging_dim_house_listing_task.set_upstream([rent_flow, property_listing, property_task])
        staging_dim_house_listing_task.set_downstream(tests_tasks)
        dim_house_listing.set_upstream(tests_tasks)
        dim_house_listing >> dim_status_over_period

        return house_dag

    @logger
    def get_property_query(self, **kwargs):
        exec_date = kwargs['execution_date']
        dim = 'property'

        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR, dim)
        query = BaseETL.get_query_from_file_name(file_name=file_path)
        query = query.format(str(exec_date))

        utils.extract_query_dim_from_ebdb_to_ods(dim_name=dim, bucket=DimSubDag.S3_BUCKET, command=query,
                                                 table_name='imovel')

    @logger
    def __build_data_tasks(self, dag):
        property_task = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='ODS_imovel',
            provide_context=True,
            python_callable=self.get_property_query
        )

        affiliate = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='ODS_affiliate_payments',
            python_callable=utils.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'affiliate_payments',
                'file_name': 'affiliate_payments.sql',
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        rent_flow = BaseDAG.build_quintoandar_python_operator(
            task_id='ODS_rent_flow',
            dag=dag,
            python_callable=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'rental_flow',
                'table_name': 'FluxoLocacao',
                'copy_to_clean': False,
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        listing_views = BaseDAG.build_quintoandar_python_operator(
            task_id='ODS_listing_views',
            dag=dag,
            python_callable=utils.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'listing_views',
                'file_name': 'listing_views.sql',
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        property_listing = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='ODS_property_listing',
            python_callable=utils.materialize_view_ods,
            op_kwargs={
                'view_name': 'property_listing',
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        staging_dim_house_listing_task = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='STAGING_dim_house_listing',
            python_callable=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'property'
            }
        )

        dim_house_listing = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='DW_dim_house_listing',
            python_callable=utils.load_dim_from_staging_to_dw,
            op_kwargs={
                'dim_name': 'property',
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        dim_status_over_period = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='DW_dim_house_listing_status_over',
            python_callable=utils.load_dim_from_ods_to_dw,
            op_kwargs={
                'dim_name': 'property_status_over_period',
                'insert_dummy': False,
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        return (property_task, affiliate, rent_flow, listing_views, property_listing, staging_dim_house_listing_task,
                dim_house_listing, dim_status_over_period)
