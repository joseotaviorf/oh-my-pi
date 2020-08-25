from abc import abstractmethod

from airflow.executors.celery_executor import CeleryExecutor
from airflow.operators.subdag_operator import SubDagOperator

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum


class BaseSubDAG(object):
    """
    Base class for building the sub-dag flow.
    """

    # To do: Refactor spark jobs to set layer param and remove None value
    def __init__(
        self, sub_dag_name, dag_name, schedule_interval, start_date, layer=None
    ):
        self.sub_dag_name = sub_dag_name
        self.dag_name = dag_name
        self.schedule_interval = schedule_interval
        self.start_date = start_date

        # To do: after refactor, remove "if layer".
        if layer and not LayerEnum.is_layer_valid(layer):
            raise ValueError(f"m=__init__, layer={layer}, msg=The layer is invalid.")

        self.layer = layer

    def _build_local_dag(self):  # Todo: make public method
        """
        Builds a subdag with its default parameters
        :return: the new subdag
        """
        local_dag = BaseDAG.build_dag(
            f"{self.dag_name}.{self.sub_dag_name}",
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

    def build_subdags_from_sql_files(
        self, dag, file_list, test_ods_migration=False, **kwargs
    ):
        """
        Return a subdag for each table in a specified file list containing table's sqls
        :param dag: main dag to attach subdag to
        :param file_list: list of files containing sql queries for each table
        :param layer: layer that table belongs to
        :param test_ods_migration: If true, adds a migration test task
        :return: a list of table name/subdag created
        """
        subdags = {}
        for file_name in file_list:
            slugged_table_name = file_name.replace("_", "-")
            slugged_layer = self.layer.value.replace("_", "-")
            table_sub_dag = BaseSubDAG.get_sub_dag_operator(
                dag=dag,
                sub_dag_name=f"load-{slugged_table_name}-to-{slugged_layer}",
                sub_dag_func=self.build_subdag,
                table_name=file_name,
                slugged_table_name=slugged_table_name,
                test_ods_migration=test_ods_migration,
                **kwargs,
            )
            subdags[file_name] = table_sub_dag

        return subdags

    @abstractmethod
    def build_subdag(
        self, sub_dag_name, table_name, slugged_table_name, test_ods_migration
    ):
        """
        Create the subdag following logic for each concrete class.
        It must be implemented in each concrete class.
        :param sub_dag_name: subdag name
        :param table_name: table name for the subdag
        :param slugged_table_name: slugged table name for the subdag
        :return: the subdag created
        """
        raise NotImplementedError()
