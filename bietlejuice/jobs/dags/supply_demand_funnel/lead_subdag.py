from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.new_etl.business_dim_etl import BusinessDimensionETL
from qa_python_utils.default_logger import logger

biz_etl = BusinessDimensionETL('5a-datalake')


class LeadSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        self.sub_dag_name = sub_dag_name
        self.dag_name = dag_name
        self.schedule_interval = schedule_interval
        self.start_date = start_date

        self.bucket = bucket

    @logger
    def build(self):
        lead_dag = self.__build_local_dag()

        lead, dim_lead = self.__build_data_tasks(lead_dag)

        test_count = self.__build_tests_tasks(lead_dag)

        lead >> dim_lead >> test_count

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
            func_command=self.__extract_query_dim_from_ebdb_to_ods,
            op_kwargs={'dim_name': 'lead', 'bucket': self.bucket, 'command': 'call ebdb.list_lead();'}
        )

        dim_lead = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='DW_dim_lead',
            func_command=self.__load_dim_from_ods_to_dw,
            op_kwargs={'dim_name': 'lead', 'bucket': self.bucket}
        )

        return lead, dim_lead

    @logger
    def __build_tests_tasks(self, dag):

        test_lead = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='TEST_dim_lead',
            func_command=self.__test_lead_count
        )

        return test_lead

    @staticmethod
    def __test_lead_count():
        return True

    @staticmethod
    def __extract_query_dim_from_ebdb_to_ods(**kwargs):
        biz_etl.extract_query_dim_from_ebdb_to_ods(
            dim_name=kwargs['dim_name'],
            command=kwargs['command'],
            table_name=None if 'table_name' not in kwargs else kwargs['table_name']
        )

    @staticmethod
    def __load_dim_from_ods_to_dw(**kwargs):
        biz_etl.load_dim_from_ods_to_dw(
            dim_name=kwargs['dim_name'],
            insert_dummy=True if 'insert_dummy' not in kwargs else kwargs['insert_dummy'],
            is_fact=False if 'is_fact' not in kwargs else kwargs['is_fact'],
            pre_command=None if 'pre_command' not in kwargs else kwargs['pre_command'],
            post_command=None if 'post_command' not in kwargs else kwargs['post_command']
        )
