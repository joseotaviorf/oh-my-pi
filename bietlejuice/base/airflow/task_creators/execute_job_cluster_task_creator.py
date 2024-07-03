from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.services.configuration_service import ConfigurationService
from databricks_plugin import QuintoAndarDatabricksExecuteJobClusterOperator


class ExecuteJobClusterTaskCreator(BaseTaskCreator):
    """Creates the task that executes a Databricks Job Cluster"""

    _TASK_ID = "execute-job-cluster"

    def __init__(
        self,
        dag_execution_context: DagExecutionContext,
        config_service: ConfigurationService,
        minimum_databricks_version: str = None,
    ):
        super().__init__(dag_execution_context)
        self.cluster_args = dag_execution_context.cluster_args
        self.config_service = config_service
        self.minimum_databricks_version = minimum_databricks_version
        if minimum_databricks_version:
            self.minimum_databricks_major_version = int(
                minimum_databricks_version.split(".")[0]
            )
            self.minimum_databricks_minor_version = int(
                minimum_databricks_version.split(".")[1]
            )

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

    def __validate_databricks_version(self, cluster_configuration: dict):
        if self.minimum_databricks_version:
            current_databricks_version = cluster_configuration.get("spark_version")
            current_databricks_major_version = int(
                current_databricks_version.split(".")[0]
            )
            current_databricks_minor_version = int(
                current_databricks_version.split(".")[1]
            )
            if (
                current_databricks_major_version < self.minimum_databricks_major_version
                or (
                    current_databricks_major_version
                    == self.minimum_databricks_major_version
                    and current_databricks_minor_version
                    < self.minimum_databricks_minor_version
                )
            ):
                raise ValueError(
                    f"Current Databricks version ({current_databricks_version}) is below the minimum required version ({self.minimum_databricks_version})"
                )

    def __get_libraries(self) -> list:
        default_libraries = self.config_service.get_config("default_libraries")
        custom_libraries = [
            (
                {
                    lib_type: lib_name.format(
                        artifacts_bucket=self.config_service.get_config(
                            "artifacts_bucket"
                        )
                    )
                }
                if isinstance(lib_name, str)
                else {lib_type: lib_name}
            )
            for custom_libraries in self.cluster_args.get("custom_libraries", [])
            for lib_type, lib_name in custom_libraries.items()
        ]
        libraries = default_libraries + custom_libraries
        return libraries

    def create_task(
        self, execute_job_cluster_local_id=None
    ) -> QuintoAndarDatabricksExecuteJobClusterOperator:
        """
        Creates the ExecuteJobCluster task to enable Spark Jobs to run on Databricks Job Cluster

        :param execute_job_cluster_local_id: This param adds a suffix with this ID to the task name, since a DAG can have multiple `execute-job-cluster` tasks due to Job Cluster API 100 tasks limitation.
        """
        cluster_configuration = self.__get_cluster_configuration()
        self.__validate_databricks_version(cluster_configuration)
        if execute_job_cluster_local_id:
            task_id = f"{self._TASK_ID}-{execute_job_cluster_local_id}"
        else:
            task_id = self._TASK_ID

        return QuintoAndarDatabricksExecuteJobClusterOperator(
            databricks_conn_id="databricks_job_cluster",
            dag=self.dag_execution_context.dag,
            task_id=task_id,
            cluster_configuration=cluster_configuration,
            libraries=self.__get_libraries(),
            access_control_list=self.__get_access_control_list(),
        )
