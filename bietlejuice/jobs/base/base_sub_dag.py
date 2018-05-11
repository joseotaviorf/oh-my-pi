from airflow.operators.subdag_operator import SubDagOperator
from qa_python_utils.default_logger import logger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG


class BaseSubDag(object):
    """
    Base class for building the subdag flow, which includes main and tests tasks
    """

    @logger
    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date, ebdb_table_name=None):
        self.sub_dag_name = sub_dag_name
        self.dag_name = dag_name
        self.schedule_interval = schedule_interval
        self.start_date = start_date
        self.ebdb_table_name = ebdb_table_name
        self.bucket = bucket

    @logger
    def _build_local_dag(self):
        """
        Builds a subdag with its default parameters
        :return: the new subdag
        """
        local_dag = BaseDAG.build_dag(
            '{}.{}'.format(self.dag_name, self.sub_dag_name),
            schedule_interval=self.schedule_interval,
            start_date=self.start_date,
        )

        return local_dag

    @staticmethod
    @logger(exclude='dag')
    def get_sub_dag_operator(dag, sub_dag_name, sub_dag_func):
        """
        Gets the corresponding subdag operator statically
        :param dag: the main dag which will contain the subdag
        :param sub_dag_func: the method for building the subdag
        :return: the new subdag operator
        """
        return SubDagOperator(
            subdag=sub_dag_func(sub_dag_name),
            task_id=sub_dag_name,
            dag=dag,
        )

    @logger
    def _build(self, entity):
        """
        Method for calling the entity subdag with its etl tasks and building the entire flow
        :param entity: name of the entity that composes the subdag
        :return: the entity dag
        """
        entity_dag = self._build_local_dag()
        entity, staging_dim_entity, load_entity = self._build_data_tasks(entity_dag, entity)

        # flow
        entity >> staging_dim_entity >> load_entity

        return entity_dag

    @logger
    def _build_with_tests(self, entity, source_command, tests, table_name=None):
        """
        Method for calling the entity subdag with its etl and tests tasks and building the entire flow
        :param entity: name of the entity that composes the subdag
        :param source_command: command string for calling source data retrieval method
        :param tests: list of test tuples to be built (ex: ('test_task_id_suffix', test_method))
        :return: the entity dag
        """
        entity_dag = self._build_local_dag()
        entity, staging_dim_entity, load_entity = self._build_data_tasks(entity_dag, entity, source_command, table_name)

        tests_tasks = self._build_tests_tasks(entity_dag, tests)

        # flow
        entity >> staging_dim_entity
        staging_dim_entity.set_downstream(tests_tasks)
        load_entity.set_upstream(tests_tasks)

        return entity_dag

    @logger
    def _build_data_tasks(self, dag, entity, source_command, table_name=None):
        """
        Method for building all the main tasks for the etl step
        :param dag: the dag which the tasks will be in
        :param entity: name of the entity that composes the subdag
        :param source_command: command string for calling source data retrieval method
        :return: the main tasks related to the etl step
        """
        entity_task = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='ODS_{}'.format(entity),
            func_command=utils.extract_query_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': entity,
                'bucket': self.bucket,
                'command': source_command,
                'table_name': table_name
            }
        )

        staging_dim_entity_task = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='STAGING_dim_{}'.format(entity),
            func_command=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': entity
            }
        )

        load_entity_task = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='DW_dim_{}'.format(entity),
            func_command=utils.load_dim_from_staging_to_dw,
            op_kwargs={
                'dim_name': entity,
                'bucket': self.bucket
            }
        )

        return entity_task, staging_dim_entity_task, load_entity_task

    @logger
    def _build_tests_tasks(self, dag, tests):
        """
        Builds all the test tasks for a specific dag/subdag
        :param dag: the dag which the tasks will be in
        :param tests: list of test tuples to be built (ex: ('test_task_id_suffix', test_method))
        :return: the test tasks for the corresponding dag
        """
        tests_tasks = []
        for _test in tests:
            test_task = BaseDAG.get_quintoandar_python_operator(
                dag=dag,
                task_id='TEST_{}'.format(_test[0]),
                func_command=_test[1]
            )

            tests_tasks.append(test_task)

        return tests_tasks
