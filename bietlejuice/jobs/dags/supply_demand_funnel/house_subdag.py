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
            table_name='Imovel',
            ods_stg_table_name='house_listing'
        )

    @logger
    def build_house_with_tests(self):
        house_dag = self._build_local_dag()

        (portability, house_task, affiliate, rent_flow, house_listing,
         staging_dim_house_listing_task,
         listing_business_context) = self.__build_data_tasks(house_dag)

        # TODO: put tests back to flow
        # tests_tasks = self.build_tests_tasks(house_dag)

        affiliate >> house_listing
        staging_dim_house_listing_task.set_upstream(
            [portability, rent_flow, house_listing, house_task, listing_business_context])
        # staging_dim_house_listing_task.set_downstream(tests_tasks)
        # dim_house_listing.set_upstream(tests_tasks)

        return house_dag

    @logger
    def extract_from_ebdb_to_ods_with_query(self, table_name, execution_date, **kwargs):
        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR,
                                                                 table_name)
        query = BaseETL.get_query_from_file_name(file_name=file_path)
        query = query.format(str(execution_date))

        utils.extract_query_dim_from_ebdb_to_ods(dim_name=table_name,
                                                 bucket=self.bucket,
                                                 command=query)

    @logger
    def __build_data_tasks(self, dag):
        property_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_imovel',
            provide_context=True,
            python_callable=self.extract_from_ebdb_to_ods_with_query,
            op_kwargs={'table_name': 'house'}
        )

        portability = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_portability',
            provide_context=True,
            python_callable=self.extract_from_ebdb_to_ods_with_query,
            op_kwargs={'table_name': 'portability'}
        )

        affiliate = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_affiliate_payments',
            python_callable=utils.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'affiliate_payments',
                'file_name': 'affiliate_payments.sql',
                'bucket': self.bucket
            }
        )

        rent_flow = BaseDAG.build_python_operator(
            task_id='ODS_rent_flow',
            dag=dag,
            python_callable=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'rental_flow',
                'table_name': 'FluxoLocacao',
                'copy_to_clean': False,
                'bucket': self.bucket
            }
        )

        house_listing_task = BaseDAG.build_python_operator(
            task_id='ODS_house_listing',
            dag=dag,
            python_callable=utils.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'house_listing',
                'file_name': 'house/house_listing.sql',
                'bucket': self.bucket
            }
        )

        staging_dim_house_listing_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='STAGING_dim_house_listing',
            python_callable=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'house_listing'
            }
        )

        listing_business_context = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_listing_business_context',
            provide_context=True,
            python_callable=self.extract_from_ebdb_to_ods_with_query,
            op_kwargs={'table_name': 'listing_business_context'}
        )

        return (portability, property_task, affiliate, rent_flow, house_listing_task,
                staging_dim_house_listing_task, listing_business_context)
