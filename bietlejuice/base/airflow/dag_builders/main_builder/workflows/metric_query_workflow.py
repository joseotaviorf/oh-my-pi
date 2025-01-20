from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.pipeline import LayerEnum


class MetricQueryWorkflow(BaseWorkflow):
    """
    Inherits the dag build base to define the flow that creates tasks from sql files.
    :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
    :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
    :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
    """

    BUSINESS_DOMAIN_DELIMITER = "__"

    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args)
        self.databricks_conn_id = self.cluster_args.get(
            "databricks_conn_id", "databricks_default"
        )

    def build_dag(self):
        tables_customization = self.workflow_args.get("tables_customization", {})
        default_partitions = self.workflow_args.get("default_partitions")
        default_is_incremental = (
            self.workflow_args.get("default_extraction_type") == "incremental"
        )
        inner_dependencies = self.workflow_args.get("inner_dependencies")
        cluster_params = self.get_cluster_params()

        metrics_bucket = self.config_service.get_config("metrics_bucket")
        databricks_bietlejuice_repo_path = self.config_service.get_config(
            "databricks_bietlejuice_repo_path"
        )
        base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
        business_unit = self.dag_name.split(self.BUSINESS_DOMAIN_DELIMITER)[0]
        source_database_base_name = business_unit.replace("metric_", "")
        target_database_base_name = source_database_base_name

        dag = self.dag_instance()

        task_group = DatalakeTaskGroup(
            dag=dag,
            env=self.env,
            datalake_bucket=metrics_bucket,
            relative_query_path=self.dag_name,
            spark_jobs_path=base_spark_jobs_path,
            databricks_conn_id=self.databricks_conn_id,
        )

        metric_task_group = task_group.build_task_group_from_sql_files(
            layer=LayerEnum.METRIC,
            source_database_base_name=source_database_base_name,
            target_database_base_name=target_database_base_name,
            tables_customization=tables_customization,
            partitions=default_partitions,
            is_incremental=default_is_incremental,
        )

        create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
            dag=dag,
            task_id="create-cluster",
            cluster_configuration=cluster_params["cluster_config"],
            libraries=cluster_params["default_libraries"],
            access_control_list=cluster_params["access_control_list"],
            databricks_conn_id=self.databricks_conn_id,
        )
        terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
            dag=dag,
            task_id="terminate-cluster",
            databricks_conn_id=self.databricks_conn_id,
        )

        self.set_dependencies(
            inner_dependencies,
            task_group,
            create_cluster_task,
            terminate_cluster_task,
            metric_task_group,
        )

        return dag

    def get_cluster_params(self):
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
            "cluster_config": cluster_configuration,
            "default_libraries": default_libraries,
            "access_control_list": databricks_access_control_list,
        }

    def set_dependencies(
        self,
        inner_dependencies,
        task_group,
        create_cluster_task,
        terminate_cluster_task,
        metric_task_group,
    ):
        if inner_dependencies:
            (
                task_groups_boundaries_without_inner_dependencies,
                inner_dependencies_task_groups_boundaries,
            ) = task_group.set_inner_dag_dependencies(
                task_flow_helper=TaskFlowHelper(),
                task_groups_boundaries=metric_task_group,
                dag_inner_dependencies=inner_dependencies,
            )

            create_cluster_task.set_downstream(
                DatalakeTaskGroup.all_first_tasks(
                    task_groups_boundaries_without_inner_dependencies
                )
                + DatalakeTaskGroup.first_tasks(
                    inner_dependencies_task_groups_boundaries
                )
            )
        else:
            create_cluster_task.set_downstream(
                DatalakeTaskGroup.all_first_tasks(metric_task_group)
            )

        terminate_cluster_task.set_upstream(
            DatalakeTaskGroup.all_last_tasks(metric_task_group)
        )

        # Set data quality tasks if exists
        independent_tasks = DatalakeTaskGroup.all_independent_tasks(metric_task_group)
        if independent_tasks:
            terminate_cluster_task.set_upstream(independent_tasks)
