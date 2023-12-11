from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from databricks_plugin import QuintoAndarDatabricksExecuteJobClusterOperator


class ExecuteJobClusterTaskCreator(BaseTaskCreator):
    """Creates the task that executes a Databricks Job Cluster"""

    _TASK_ID = "execute-job-cluster"

    def __init__(self, dag_execution_context, config_service):
        super().__init__(dag_execution_context)
        self.cluster_args = dag_execution_context.cluster_args
        self.config_service = config_service

    def __get_access_control_list(self) -> list:
        # TODO: change access_control_list to be a list of dicts directly in the DAG declarations
        return [
            self.cluster_args.get(
                "access_control_list",
                self.config_service.get_config("default_access_control_list")[0],
            )
        ]

    def __get_cluster_configuration(self) -> dict:
        cluster_type = self.cluster_args.get("type")
        cluster_configuration = self.config_service.get_config(cluster_type)
        updated_cluster_configuration = self.config_service._deep_update(
            cluster_configuration, self.cluster_args.get("custom_configurations", {})
        )
        return updated_cluster_configuration

    def __get_libraries(self) -> list:
        default_libraries = self.config_service.get_config("default_libraries")
        # TODO: add custom_libraries feature
        return default_libraries

    def create_task(self) -> QuintoAndarDatabricksExecuteJobClusterOperator:
        """
        Creates the ExecuteJobCluster task to enable Spark Jobs to run on Databricks Job Cluster
        """

        return QuintoAndarDatabricksExecuteJobClusterOperator(
            databricks_conn_id="databricks_job_cluster",
            dag=self.dag_execution_context.dag,
            task_id=self._TASK_ID,
            cluster_configuration=self.__get_cluster_configuration(),
            libraries=self.__get_libraries(),
            access_control_list=self.__get_access_control_list(),
        )
