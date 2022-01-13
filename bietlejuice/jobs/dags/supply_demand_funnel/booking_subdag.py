from datetime import datetime
from qa_python_utils import QuintoAndarLogger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag

logger = QuintoAndarLogger('BookingSubDag')


class BookingSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(BookingSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name='Agendamento',
            ods_stg_table_name='booking'
        )

    @logger
    def build_booking_with_tests(self):
        booking_dag = self._build_local_dag()

        bookings, property_booking_information, staging_dim_booking_task = self.__build_data_tasks(
            booking_dag)

        tests_tasks = self.build_tests_tasks(booking_dag)

        property_booking_information >> bookings
        bookings >> staging_dim_booking_task
        staging_dim_booking_task.set_downstream(tests_tasks)

        return booking_dag

    @logger
    def get_booking_query(self, **kwargs):
        exec_date = kwargs['execution_date']
        dim = 'booking'

        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR, dim)
        query = BaseETL.get_query_from_file_name(file_name=file_path)
        query = query.format(str(exec_date))

        utils.extract_query_dim_from_ebdb_to_ods(dim_name=dim, bucket=self.bucket, command=query,
                                                 table_name=None)

    @logger
    def __build_data_tasks(self, dag):
        booking = BaseDAG.build_python_operator(
            task_id='ODS_booking',
            dag=dag,
            provide_context=True,
            python_callable=self.get_booking_query
        )

        booking_media_sources_task = BaseDAG.build_python_operator(
            task_id='ODS_booking_media_sources',
            dag=dag,
            python_callable=utils.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'booking_media_sources',
                'file_name': 'extract_booking_media_sources.sql',
                'bucket': self.bucket
            }
        )

        staging_dim_booking_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='STAGING_dim_booking',
            python_callable=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'booking',
                'post_command': "update staging.dim_booking set ts_load = '{}' where sk_booking = -1;".format(
                    datetime.now().strftime('%Y-%m-%d'))
            }
        )


        return booking, booking_media_sources_task, staging_dim_booking_task
