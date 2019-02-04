from qa_python_utils import QuintoAndarLogger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.enum_db import EnumDB

logger = QuintoAndarLogger('ReservationSubDag')


class ReservationSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(ReservationSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name='reservation',
        )
        self.ods_stg_table_name = 'reservation'

    @logger
    def build_tasks_with_tests(self):
        reservation_dag = self._build_local_dag()

        reservation_to_ods_task = BaseDAG.build_python_operator(
            task_id='reservation_to_ods',
            dag=reservation_dag,
            python_callable=utils.load_athena_query_to_ods,
            op_kwargs={
                'dim_name': 'reservation',
                'bucket': self.bucket,
                'fname': 'kill_queue/reservation_clean'
            }
        )
        staging_dim_reservation_task = BaseDAG.build_python_operator(
            dag=reservation_dag,
            task_id='STAGING_dim_reservation',
            python_callable=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'reservation',
            }
        )

        # TODO refactor DimSubdag to put this class to inherit from it and not include these tests here
        tests_tasks = self.create_tests_tasks(
            dag=reservation_dag,
        )

        dim_reservation_task = BaseDAG.build_python_operator(
            task_id='DW_dim_reservation',
            dag=reservation_dag,
            python_callable=utils.load_dim_from_staging_to_dw,
            op_kwargs={
                'dim_name': 'reservation',
                'bucket': self.bucket
            }
        )

        reservation_to_ods_task.set_downstream(staging_dim_reservation_task)
        staging_dim_reservation_task.set_downstream(tests_tasks)
        dim_reservation_task.set_upstream(tests_tasks)

        return reservation_dag

    @logger
    def create_tests_tasks(self, dag):
        return self._build_tests_tasks(
            dag=dag,
            tests=[
                ('duplicates_dim_{}'.format(self.ods_stg_table_name), self.__test_duplicates),
                ('emptiness_dim_{}'.format(self.ods_stg_table_name), self.__test_emptiness),
                ('counts_dim_{}'.format(self.ods_stg_table_name),
                 self.__test_counts_from_raw_query)
            ]
        )

    def __test_duplicates(self):
        BaseTest.check_for_duplicates(
            schema='staging',
            table='dim_{}'.format(self.ods_stg_table_name),
            key='sk_{}'.format(self.ods_stg_table_name),
            enum_db=EnumDB.BI_ODS
        )

    def __test_emptiness(self):
        BaseTest.check_for_emptiness(
            schema='staging',
            table='dim_{}'.format(self.ods_stg_table_name),
            enum_db=EnumDB.BI_ODS
        )

    def __test_counts_from_raw_query(self):
        BaseTest.are_counts_equal({
            'acceptable_diff': .5,
            'sources': [
                {
                    'schema': 'staging',
                    'table_name': 'dim_{}'.format(self.ods_stg_table_name),
                    'enum_db': EnumDB.BI_ODS
                },
                {
                    'schema': 'killqueue',
                    'table_name': self.table_name,
                    'enum_db': EnumDB.QuintoAndar_killqueue,
                    'encoding': 'LATIN1'
                }
            ]
        })
