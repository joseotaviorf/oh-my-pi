from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.new_etl import dim_utils as utils
from qa_python_utils.default_logger import logger


class PhotoJobSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        self.sub_dag_name = sub_dag_name
        self.dag_name = dag_name
        self.schedule_interval = schedule_interval
        self.start_date = start_date

        self.bucket = bucket

    @logger
    def build(self):
        lead_dag = self.__build_local_dag()

        photo_job, dim_photo_job = self.__build_data_tasks(lead_dag)

        test_photo_job = self.__build_tests_tasks(lead_dag)

        photo_job >> dim_photo_job >> test_photo_job

        return lead_dag

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
            task_id='DW_dim_photo_job',
            func_command=utils.load_dim_from_ods_to_dw,
            op_kwargs={'dim_name': 'photo_job', 'bucket': self.bucket}
        )

        return photo_job, dim_photo_job

    @logger
    def __build_tests_tasks(self, dag):
        test_photo_job = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='TEST_dim_photo_job',
            func_command=self.__test_lead_count
        )

        return test_photo_job

    @staticmethod
    def __test_lead_count():
        return True
