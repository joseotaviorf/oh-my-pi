from datetime import datetime

from qa_python_utils.default_logger import logger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag


class RegionSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(RegionSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='regiao',
            ods_stg_table_name='region'
        )

    @logger
    def build_region_with_tests(self):
        region_dag = self._build_local_dag()

        agent_region, region, dim_region, load_region = self.__build_data_tasks(region_dag)

        tests_tasks = self.build_tests_tasks(region_dag)

        dim_region.set_upstream([agent_region, region])
        dim_region.set_downstream(tests_tasks)
        load_region.set_upstream(tests_tasks)

        return region_dag

    @logger
    def __build_data_tasks(self, dag):
        agent_region = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_agent_region',
            dag=dag,
            func_command=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'agent_region',
                'table_name': 'DadosAgente_Regiao',
                'copy_to_clean': False,
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        region = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='ODS_region',
            func_command=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'region',
                'table_name': 'MapRegiao',
                'add_timestamp': True,
                'copy_to_clean': False,
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        dim_region = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='STAGING_dim_region',
            func_command=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'region',
                'post_command': "update staging.dim_region set dt_timestamp = '{}' where sk_region = -1;".format(
                    datetime.now().strftime('%Y-%m-%d'))
            }
        )

        load_region = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='DW_dim_region',
            func_command=utils.load_dim_from_staging_to_dw,
            op_kwargs={
                'dim_name': 'region'
            }
        )

        return agent_region, region, dim_region, load_region
