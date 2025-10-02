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
        cluster_configuration = self.__input_spark_env_vars(cluster_configuration)
        self.__validate_databricks_version(cluster_configuration)
        if execute_job_cluster_local_id:
            task_id = f"{self._TASK_ID}-{execute_job_cluster_local_id}"
        else:
            task_id = self._TASK_ID

        return QuintoAndarDatabricksExecuteJobClusterOperator(
            databricks_conn_id=self.dag_execution_context.databricks_conn_id,
            dag=self.dag_execution_context.dag,
            task_id=task_id,
            cluster_configuration=cluster_configuration,
            libraries=self.__get_libraries(),
            access_control_list=self.__get_access_control_list(),
        )

    def __get_spark_version(self, databricks_version: str) -> str:
        spark_map = {
            # These are not the real spark versions
            # This will only be used to determine the inmetro and deequ libraries
            "12.2.x-scala2.12": "3.2",  # This is actually 3.3
            "13.3.x-scala2.12": "3.2",  # And this is actually 3.4
            "14.3.x-scala2.12": "3.5",
            "15.4.x-scala2.12": "3.5",
            "16.4.x-scala2.12": "3.5",
        }
        try:
            return spark_map[databricks_version]
        except KeyError as exc:
            raise ValueError(f"Invalid DBR version: {databricks_version}") from exc

    def __input_inmetro_version(self, spark_version: str) -> str:
        inmetro_map = {
            "3.2": "2.3.0",  # Databricks 12.2 and 13.3 - keep compatibility
            "3.3": "4.10.1",  # Databricks 14.3+ - new version with content parameter support
            "3.4": "4.10.1",
            "3.5": "4.10.1",
        }

        try:
            return inmetro_map[spark_version]
        except KeyError as exc:
            raise ValueError(f"Invalid Spark version: {spark_version}") from exc

    def __input_deequ_version(self, spark_version: str) -> str:
        deequ_map = {"3.2": "2.0.1", "3.3": "2.0.8", "3.4": "2.0.8", "3.5": "2.0.8"}

        try:
            return deequ_map[spark_version]
        except KeyError as exc:
            raise ValueError(f"Invalid Spark version: {spark_version}") from exc

    def __input_databricks_default_service_credential_name(
        self, cluster_configuration: dict
    ) -> dict:
        dbr_version = cluster_configuration["spark_version"]
        data_security_mode = cluster_configuration["data_security_mode"]

        if data_security_mode == "USER_ISOLATION" and dbr_version >= "16.4":
            cluster_configuration["spark_env_vars"][
                "DATABRICKS_DEFAULT_SERVICE_CREDENTIAL_NAME"
            ] = self.config_service.get_config(
                "databricks_default_service_credential_name"
            )
        return cluster_configuration

    def __input_spark_env_vars(self, cluster_configuration: dict) -> dict:
        cluster_configuration["spark_env_vars"][
            "SPARK_VERSION"
        ] = self.__get_spark_version(cluster_configuration["spark_version"])
        cluster_configuration["spark_env_vars"][
            "INMETRO_VERSION"
        ] = self.__input_inmetro_version(
            cluster_configuration["spark_env_vars"]["SPARK_VERSION"]
        )
        cluster_configuration["spark_env_vars"][
            "DEEQU_JAR_VERSION"
        ] = self.__input_deequ_version(
            cluster_configuration["spark_env_vars"]["SPARK_VERSION"]
        )
        cluster_configuration = self.__input_databricks_default_service_credential_name(
            cluster_configuration
        )
        return cluster_configuration
