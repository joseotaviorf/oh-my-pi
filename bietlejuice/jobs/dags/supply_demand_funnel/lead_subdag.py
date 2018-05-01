from qa_python_utils.default_logger import logger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.enum_db import EnumDb


class LeadSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(LeadSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)

    @logger
    def build(self):
        lead_dag = self.__build_local_dag()

        lead, dim_lead, load_lead = self.__build_data_tasks(lead_dag)

        duplicate_lead, empty_lead = self.__local_build_tests_tasks(lead_dag)

        lead >> dim_lead >> empty_lead >> duplicate_lead >> load_lead

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
        lead = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='ODS_lead',
            func_command=utils.extract_query_dim_from_ebdb_to_ods,
            op_kwargs={'dim_name': 'lead', 'bucket': self.bucket, 'command': 'call ebdb.list_lead();'}
        )

        dim_lead = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='STAGING_dim_lead',
            func_command=utils.load_dim_from_ods_to_staging,
            op_kwargs={'dim_name': 'lead'}
        )

        load_lead = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='DW_dim_lead',
            func_command=utils.load_dim_from_staging_to_dw,
            op_kwargs={'dim_name': 'lead', 'bucket': self.bucket}
        )

        return lead, dim_lead, load_lead

    @logger
    def __local_build_tests_tasks(self, dag):
        duplicate_lead = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='TEST_duplicates_dim_lead',
            func_command=self.__test_duplicates
        )

        empty_lead = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='TEST_emptiness_dim_lead',
            func_command=self.__test_duplicates
        )

        return duplicate_lead, empty_lead

    @staticmethod
    def __test_duplicates():
        BaseTest.check_for_duplicates(
            schema='staging',
            table='dim_lead',
            key='sk_lead',
            enum_db=EnumDb.BI_ODS
        )

    @staticmethod
    def __test_emptiness():
        BaseTest.check_for_emptiness(
            schema='staging',
            table='dim_lead',
            enum_db=EnumDb.BI_ODS
        )
