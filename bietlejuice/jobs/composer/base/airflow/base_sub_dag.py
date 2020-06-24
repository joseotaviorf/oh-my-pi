from abc import abstractmethod

from airflow.executors.celery_executor import CeleryExecutor
from airflow.operators.subdag_operator import SubDagOperator

from bietlejuice.jobs.composer.base.airflow import BaseDAG


class BaseSubDAG(object):
    """
    Base class for building the sub-dag flow.
    """

    def __init__(self, sub_dag_name, dag_name, schedule_interval, start_date):
        self.sub_dag_name = sub_dag_name
        self.dag_name = dag_name
        self.schedule_interval = schedule_interval
        self.start_date = start_date

    def _build_local_dag(self):  # Todo: make public method
        """
        Builds a subdag with its default parameters
        :return: the new subdag
        """
        local_dag = BaseDAG.build_dag(
            "{}.{}".format(self.dag_name, self.sub_dag_name),
            schedule_interval=self.schedule_interval,
            start_date=self.start_date,
        )

        return local_dag

    @staticmethod
    def get_sub_dag_operator(dag, sub_dag_name, sub_dag_func, **kwargs):
        """
        Gets a sub-dag operator.
        :param dag: the main dag which will contain the subdag
        :param sub_dag_func: the method for building the subdag
        :return: the new subdag operator
        """
        return SubDagOperator(
            subdag=sub_dag_func(sub_dag_name, **kwargs),
            task_id=sub_dag_name,
            dag=dag,
            executor=CeleryExecutor(),
        )

    def build_subdags_from_sql_files(self, dag, file_list, layer):
        """
        Return a subdag for each table in a specified file list containing table's sqls
        :param dag: main dag to attach subdag to
        :param file_list: list of files containing sql queries for each table
        :param layer: layer that table belongs to
        :return: a list of table name/subdag created
        """
        subdags = {}
        for file_name in file_list:
            slugged_table_name = file_name.replace("_", "-")
            table_sub_dag = BaseSubDAG.get_sub_dag_operator(
                dag=dag,
                sub_dag_name=f"load-{slugged_table_name}-to-{layer}",
                sub_dag_func=self.build_subdag,
                table_name=file_name,
                slugged_table_name=slugged_table_name,
            )
            subdags[file_name] = table_sub_dag

        return subdags

    @abstractmethod
    def build_subdag(self, sub_dag_name, table_name, slugged_table_name):
        """
        Create the subdag following logic for each concrete class.
        It must be implemented in each concrete class.
        :param sub_dag_name: subdag name
        :param table_name: table name for the subdag
        :param slugged_table_name: slugged table name for the subdag
        :return: the subdag created
        """
        raise NotImplementedError()
