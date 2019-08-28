from airflow.executors.celery_executor import CeleryExecutor
from airflow.operators.subdag_operator import SubDagOperator
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.airflow import BaseDAG

logger = QuintoAndarLogger("BaseSubDAG")


class BaseSubDAG(object):
    """
    Base class for building the sub-dag flow.
    """

    @logger
    def __init__(
        self,
        sub_dag_name,
        dag_name,
        schedule_interval,
        start_date,
    ):
        self.sub_dag_name = sub_dag_name
        self.dag_name = dag_name
        self.schedule_interval = schedule_interval
        self.start_date = start_date

    @logger
    def _build_local_dag(self):
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
    @logger
    def get_sub_dag_operator(
        dag,
        sub_dag_name,
        sub_dag_func,
        **kwargs
    ):
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