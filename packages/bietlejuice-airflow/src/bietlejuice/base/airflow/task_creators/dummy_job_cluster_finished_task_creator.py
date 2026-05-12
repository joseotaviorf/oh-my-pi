from airflow.operators.python_operator import PythonOperator

from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator


class DummyJobClusterFinishedTaskCreator(BaseTaskCreator):
    """Creates a dummy task to mark that the job_cluster has finished"""

    _TASK_ID = "job-cluster-finished"

    def create_task(self) -> PythonOperator:
        """
        Creates the job-cluster-finished DummyOperator task to indicate the end of a DAG that uses Job Cluster
        """
        # Dummy Operators don't show up in Airflow's logs, because they are marked as success immediately.
        # We need the task instance to be in the logs for DAG monitoring purposes. This is why we're using a
        # PythonOperator
        return PythonOperator(
            dag=self.dag_execution_context.dag,
            task_id=self._TASK_ID,
            python_callable=lambda: "task finished",
        )
