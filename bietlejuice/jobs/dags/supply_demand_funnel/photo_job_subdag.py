from qa_python_utils.default_logger import logger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.enum_db import EnumDb


class PhotoJobSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(PhotoJobSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)

    @logger
    def build(self):
        photo_job_dag = self.__build_local_dag()

        photo_job, dim_photo_job, load_photo_job = self.__build_data_tasks(photo_job_dag)

        test_photo_job = self.__local_build_tests_tasks(photo_job_dag)

        photo_job >> dim_photo_job >> test_photo_job

        return photo_job_dag

    @logger
    def __build_local_dag(self):
        local_dag = BaseDAG.build_dag(
            '{}.{}'.format(self.dag_name, self.sub_dag_name),
            schedule_interval=self.schedule_interval,
            start_date=self.start_date,
        )

        return local_dag

    @logger
    def __build_data_tasks(self, dag):
        photo_job = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='ODS_photo_job',
            func_command=utils.extract_query_dim_from_ebdb_to_ods,
            op_kwargs={'dim_name': 'photo_job', 'bucket': self.bucket, 'command': 'call ebdb.list_photo_job();'}
        )

        dim_photo_job = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='STAGING_dim_photo_job',
            func_command=utils.load_dim_from_ods_to_staging,
            op_kwargs={'dim_name': 'photo_job'}
        )

        load_photo_job = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='DW_dim_photo_job',
            func_command=utils.load_dim_from_staging_to_dw,
            op_kwargs={'dim_name': 'photo_job', 'bucket': self.bucket}
        )

        return photo_job, dim_photo_job, load_photo_job

    @logger
    def __local_build_tests_tasks(self, dag):
        duplicate_photo_job = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='TEST_duplicates_dim_photo_job',
            func_command=self.__test_duplicates
        )

        empty_photo_job = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='TEST_emptiness_dim_photo_job',
            func_command=self.__test_duplicates
        )

        return duplicate_photo_job, empty_photo_job

    @staticmethod
    def __test_duplicates():
        BaseTest.check_for_duplicates(
            schema='staging',
            table='dim_photo_job',
            key='sk_photo_job',
            enum_db=EnumDb.BI_ODS
        )

    @staticmethod
    def __test_emptiness():
        BaseTest.check_for_emptiness(
            schema='staging',
            table='dim_photo_job',
            enum_db=EnumDb.BI_ODS
        )
