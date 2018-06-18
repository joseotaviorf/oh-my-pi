import os
from datetime import datetime

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag
from qa_python_utils.default_logger import logger

dir_path = os.path.dirname(os.path.realpath(__file__))
QUERIES_EBDB_DIR = os.path.join(dir_path, '../../../db/1.source/ebdb/queries/supply_demand_funnel')


class VisitSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(VisitSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='Visita',
            ods_stg_table_name='visit'
        )

    @logger
    def build_visit_with_tests(self):
        visit_dag = self._build_local_dag()

        visits, property_visit_information, staging_dim_visit_task, dim_visit = self.__build_data_tasks(visit_dag)

        tests_tasks = self.build_tests_tasks(visit_dag)

        property_visit_information >> visits
        visits >> staging_dim_visit_task
        staging_dim_visit_task.set_downstream(tests_tasks)
        dim_visit.set_upstream(tests_tasks)

        return visit_dag

    @logger
    def get_visit_query(self, **kwargs):
        exec_date = kwargs['execution_date']
        dim = 'visit'

        query = self.get_query(dim_name=dim)
        query = query.format(str(exec_date))

        utils.extract_query_dim_from_ebdb_to_ods(dim_name=dim, bucket=DimSubDag.S3_BUCKET, command=query,
                                                 table_name=None)

    @logger
    def get_query(self, dim_name):
        file_name = '{}/{}.sql'.format(QUERIES_EBDB_DIR, dim_name)

        with open(file_name) as f:
            lines = f.read()

        return lines

    @logger
    def __build_data_tasks(self, dag):
        visits = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_visits',
            dag=dag,
            provide_context=True,
            func_command=self.get_visit_query
            # func_command=utils.extract_query_dim_from_ebdb_to_ods,
            #
            # op_kwargs={
            #     'dim_name': 'visit',
            #     'command': 'call ebdb.list_visita();',
            #     'bucket': DimSubDag.S3_BUCKET
            # }
        )

        property_visit_information = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_property_visit_information',
            dag=dag,
            func_command=utils.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'property_visit_information',
                'append': True,
                'file_name': 'property_visit_information.sql',
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        staging_dim_visit_task = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='STAGING_dim_visit',
            func_command=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'visit',
                'post_command': "update staging.dim_visit set dt_timestamp = '{}' where sk_visit = -1;".format(
                    datetime.now().strftime('%Y-%m-%d'))
            }
        )

        dim_visit = BaseDAG.get_quintoandar_python_operator(
            task_id='DW_dim_visit',
            dag=dag,
            func_command=utils.load_dim_from_staging_to_dw,
            op_kwargs={
                'dim_name': 'visit',
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        return visits, property_visit_information, staging_dim_visit_task, dim_visit
