from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.enum_db import EnumDb
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
import bietlejuice.jobs.base.new_base_etl as utils
from qa_python_utils.default_logger import logger, _logger


class PhotoJobSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        self.sub_dag_name = sub_dag_name
        self.dag_name = dag_name
        self.schedule_interval = schedule_interval
        self.start_date = start_date

        self.bucket = bucket

    @logger
    def build(self):
        photo_job_dag = self.__build_local_dag()

        photo_job, dim_photo_job, load_photo_job = self.__build_data_tasks(photo_job_dag)

        test_photo_job = self.__build_tests_tasks(photo_job_dag)

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
    def __build_tests_tasks(self, dag):

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

        if BaseTest.check_for_duplicates(
                schema='staging',
                table='dim_photo_job',
                key='sk_photo_job',
                enum_db=EnumDb.BI_ODS):
            raise Exception

        _logger.info('m=test_duplicates {} free from duplicates'.format('dim_photo_job'))

    @staticmethod
    def __test_emptiness():

        if BaseTest.check_for_emptiness(
                schema='staging',
                table='dim_photo_job',
                enum_db=EnumDb.BI_ODS):
            raise Exception

        _logger.info('m=test_emptiness {} not empty'.format('dim_photo_job'))
