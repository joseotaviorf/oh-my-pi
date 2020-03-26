from qa_python_utils import QuintoAndarLogger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag

logger = QuintoAndarLogger('SpecialConditionSubDag')


class SpecialConditionSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(SpecialConditionSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name='SpecialCondition',
            ods_stg_table_name='special_condition'
        )

    @logger
    def build_special_condition(self):
        special_condition_dag = self._build_local_dag()
        special_condition_task, special_condition_aud_task = self.__build_data_tasks(
            special_condition_dag)

        return special_condition_dag

    @logger
    def __get_query(self, table_name, **kwargs):
        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR, table_name)
        query = BaseETL.get_query_from_file_name(file_name=file_path)

        utils.extract_query_dim_from_ebdb_to_ods(
            dim_name=table_name,
            bucket=self.bucket,
            command=query
        )

    @logger
    def __build_data_tasks(self, dag):
        special_condition_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_special_condition',
            provide_context=True,
            python_callable=self.__get_query,
            op_kwargs={
                'table_name': 'special_condition'
            }
        )

        special_condition_aud_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_special_condition_aud',
            provide_context=True,
            python_callable=self.__get_query,
            op_kwargs={
                'table_name': 'special_condition_aud'
            }
        )

        return special_condition_task, special_condition_aud_task
