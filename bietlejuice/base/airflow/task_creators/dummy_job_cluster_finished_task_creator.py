from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from airflow.operators.dummy_operator import DummyOperator


class DummyJobClusterFinishedTaskCreator(BaseTaskCreator):
    """Creates a dummy task to mark that the job_cluster has finished"""

    _TASK_ID = "job-cluster-finished"

    def create_task(self) -> DummyOperator:
        """
        Creates the job-cluster-finished DummyOperator task to indicate the end of a DAG that uses Job Cluster
        """
        return DummyOperator(dag=self.dag_execution_context.dag, task_id=self._TASK_ID)
