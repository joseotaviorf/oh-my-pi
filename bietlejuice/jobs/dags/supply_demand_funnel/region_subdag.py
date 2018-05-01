from datetime import datetime
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.enum_db import EnumDb
from bietlejuice.jobs.base.base_test import BaseTest
import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from qa_python_utils.default_logger import logger, _logger


class RegionSubDag(BaseSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(RegionSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)

    @logger
    def build(self):
        region_dag = self.__build_local_dag()

        agent_region, region, dim_region, load_region = self.__build_data_tasks(region_dag)

        duplicate_region, empty_region = self.__local_build_tests_tasks(region_dag)

        agent_region >> dim_region
        region >> dim_region
        dim_region >> empty_region
        empty_region >> duplicate_region >> load_region

        return region_dag

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

        agent_region = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_agent_region',
            dag=dag,
            func_command=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={'dim_name': 'agent_region', 'bucket': self.bucket,  'table_name': 'DadosAgente_Regiao',
                       'copy_to_clean': False}
        )

        region = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='ODS_region',
            func_command=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={'dim_name': 'region', 'bucket': self.bucket, 'table_name': 'MapRegiao', 'add_timestamp': True,
                       'copy_to_clean': False}
        )

        dim_region = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='STAGING_dim_region',
            func_command=utils.load_dim_from_ods_to_staging,
            op_kwargs={'dim_name': 'region',
                       'post_command': "update staging.dim_region set dt_timestamp = '{}' where sk_region = -1;".format(
                           datetime.now().strftime('%Y-%m-%d'))}
        )

        load_region = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='DW_dim_region',
            func_command=utils.load_dim_from_staging_to_dw,
            op_kwargs={'dim_name': 'region', 'bucket': self.bucket}
        )

        return agent_region, region, dim_region, load_region

    @logger
    def __local_build_tests_tasks(self, dag):

        duplicate_region = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='TEST_duplicates_dim_region',
            func_command=self.__test_duplicates
        )

        empty_region = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='TEST_emptiness_dim_region',
            func_command=self.__test_duplicates
        )

        return duplicate_region, empty_region

    @staticmethod
    def __test_duplicates():

        if BaseTest.contains_duplicates(
                schema='staging',
                table='dim_region',
                key='sk_region',
                enum_db=EnumDb.BI_ODS):
            raise Exception

        _logger.info('m=test_duplicates {} free from duplicates'.format('dim_region'))

    @staticmethod
    def __test_emptiness():

        if BaseTest.is_empty(
                schema='staging',
                table='dim_region',
                enum_db=EnumDb.BI_ODS):
            raise Exception

        _logger.info('m=test_emptiness {} not empty'.format('dim_region'))
