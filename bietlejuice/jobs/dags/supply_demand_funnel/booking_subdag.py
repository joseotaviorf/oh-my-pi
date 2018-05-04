from qa_python_utils.default_logger import logger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag


class BookingSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(BookingSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='agendamento',
            ods_stg_table_name='booking'
        )

    @logger
    def build_booking_with_tests(self):
        booking_dag = self._build_local_dag()

        bookings, property_booking_information, dim_bookings = self.__build_data_tasks(booking_dag)

        tests_tasks = self._build_tests_tasks(booking_dag)

        property_booking_information >> bookings
        bookings.set_downstream(tests_tasks)
        dim_bookings.set_upstream(tests_tasks)

        return booking_dag

    @logger
    def __build_data_tasks(self, dag):
        booking = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_booking',
            dag=dag,
            func_command=BookingSubDag.extract_query_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'booking',
                'command': 'call ebdb.list_agendamento();'
            }
        )

        booking_media_sources_task = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_booking_media_sources',
            dag=dag,
            func_command=BookingSubDag.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'booking_media_sources',
                'file_name': 'extract_booking_media_sources.sql'
            }
        )

        dim_booking_task = BaseDAG.get_quintoandar_python_operator(
            task_id='DW_dim_booking',
            dag=dag,
            func_command=BookingSubDag.load_dim_from_staging_to_dw,
            op_kwargs={
                'dim_name': 'booking'
            }
        )

        return booking, booking_media_sources_task, dim_booking_task

    @staticmethod
    def load_athena_file_query_to_ods(**kwargs):
        utils.load_athena_file_query_to_ods(
            table_name=kwargs['table_name'],
            file_name=kwargs['file_name'],
            bucket=DimSubDag.S3_BUCKET
        )

    @staticmethod
    def load_dim_from_staging_to_dw(**kwargs):
        utils.load_dim_from_staging_to_dw(
            dim_name=kwargs['dim_name'],
            bucket=DimSubDag.S3_BUCKET,
        )

    @staticmethod
    def extract_query_dim_from_ebdb_to_ods(**kwargs):
        utils.extract_query_dim_from_ebdb_to_ods(
            dim_name=kwargs['dim_name'],
            bucket=DimSubDag.S3_BUCKET,
            command=kwargs['command']
        )
