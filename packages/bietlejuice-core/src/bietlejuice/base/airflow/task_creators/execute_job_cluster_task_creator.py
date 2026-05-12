from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.services.configuration_service import ConfigurationService


class ExecuteJobClusterTaskCreator(BaseTaskCreator):
    """Creates the task that starts the job cluster (Databricks job or EMR create cluster)."""

    def __init__(
        self,
        dag_execution_context: DagExecutionContext,
        config_service: ConfigurationService,
        minimum_cluster_runtime_version: str = None,
    ):
        super().__init__(dag_execution_context)
        self.config_service = config_service
        self.minimum_cluster_runtime_version = minimum_cluster_runtime_version

    def create_task(self, execute_job_cluster_local_id=None) -> BaseOperator:
        """
        Creates the execute-job-cluster task so Spark jobs can run on the configured backend.

        :param execute_job_cluster_local_id: Suffix when a DAG has multiple clusters (API limits).
        """
        engine = self.dag_execution_context.job_cluster_engine
        if engine is None:
            raise ValueError(
                "job_cluster_engine must be set on DagExecutionContext (call "
                "attach_job_cluster_engine_to_context when building the context)."
            )
        return engine.create_execute_cluster_task(
            config_service=self.config_service,
            minimum_cluster_runtime_version=self.minimum_cluster_runtime_version,
            execute_job_cluster_local_id=execute_job_cluster_local_id,
        )
