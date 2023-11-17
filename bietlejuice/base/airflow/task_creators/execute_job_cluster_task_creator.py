from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from databricks_plugin import QuintoAndarDatabricksExecuteJobClusterOperator


class ExecuteJobClusterTaskCreator(BaseTaskCreator):
    """Creates the task that executes a Databricks Job Cluster"""

    _TASK_ID = "execute-job-cluster"

    def __init__(self, environment_attributes, config_service):
        super().__init__(environment_attributes)
        self.cluster_args = environment_attributes.cluster_args
        self.config_service = config_service

    def _get_cluster_params(self) -> dict:
        cluster_configuration = self.config_service.get_config(
            self.cluster_args["type"]
        )
        default_libraries = self.config_service.get_config("default_libraries")
        access_control_list_from_yml = self.cluster_args["access_control_list"]
        databricks_access_control_list = [
            {
                "group_name": access_control_list_from_yml["group_name"],
                "permission_level": access_control_list_from_yml["permission_level"],
            }
        ]
        return {
            "cluster_configuration": cluster_configuration,
            "libraries": default_libraries,
            "access_control_list": databricks_access_control_list,
        }

    def create_task(self) -> QuintoAndarDatabricksExecuteJobClusterOperator:
        """
        Creates the ExecuteJobCluster task to enable Spark Jobs to run on Databricks Job Cluster
        """
        cluster_params = self._get_cluster_params()

        return QuintoAndarDatabricksExecuteJobClusterOperator(
            databricks_conn_id="databricks_job_cluster",
            dag=self.environment_attributes.dag,
            task_id=self._TASK_ID,
            cluster_configuration=cluster_params["cluster_configuration"],
            libraries=cluster_params["libraries"],
            access_control_list=cluster_params["access_control_list"],
        )
