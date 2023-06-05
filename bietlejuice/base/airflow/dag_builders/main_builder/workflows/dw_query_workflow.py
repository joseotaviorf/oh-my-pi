import os

from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.operators.python_operator import ShortCircuitOperator
from airflow.utils.helpers import chain

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.dw_task_group import DWTaskGroup
from bietlejuice.base.airflow.short_circuit_function_enum import (
    ShortCircuitFunctionEnum,
)
from bietlejuice.base.pipeline import LayerEnum


class DWQueryWorkflow(BaseWorkflow):
    """
    Inherits the dag build base to define the flow that creates tasks from sql files.
    :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
    :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
    :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
    """

    def __init__(self, dag_args, workflow_args, cluster_args):

        super().__init__(dag_args, workflow_args, cluster_args)
        self.env = os.environ.get("ENVIRONMENT")

    def build_dag(self):
        dw_schema = self.workflow_args.get("custom_schema", self.dag_args["name"])
        tables_customization = self.workflow_args.get("tables_customization", {})
        short_circuit_customization = self.workflow_args.get(
            "short_circuit_customization", {}
        )
        default_partitions = self.workflow_args.get("default_partitions")
        default_is_incremental = (
            self.workflow_args.get("default_extraction_type") == "incremental"
        )
        has_load_to_redshift_task = self.workflow_args.get(
            "has_load_to_redshift_task", True
        )
        spark_session_configs = self.workflow_args.get("spark_session_configs", {})
        inner_dependencies = self.workflow_args.get("inner_dependencies")
        cluster_params = self.get_cluster_params()

        dw_bucket = self.config_service.get_config("dw_bucket")
        spectrum_iam_role = self.config_service.get_config("spectrum_iam_role")
        databricks_bietlejuice_repo_path = self.config_service.get_config(
            "databricks_bietlejuice_repo_path"
        )
        base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"

        dag = self.dag_instance()
        task_group = DWTaskGroup(
            dag=dag,
            env=self.env,
            dw_bucket=dw_bucket,
            dw_schema=dw_schema,
            relative_query_path=self.dag_name,
            spark_jobs_path=base_spark_jobs_path,
        )

        dw_staging_task_groups = task_group.build_task_group_from_sql_files(
            layer=LayerEnum.DW_STAGING,
            spark_session_configs=spark_session_configs,
            tables_customization=tables_customization,
            partitions=default_partitions,
            is_incremental=default_is_incremental,
        )

        dw_task_groups = task_group.build_task_group_from_sql_files(
            layer=LayerEnum.DW,
            spectrum_iam_role=spectrum_iam_role,
            tables_customization=tables_customization,
            partitions=default_partitions,
            is_incremental=default_is_incremental,
            has_load_to_redshift_task=has_load_to_redshift_task,
        )

        skip_run_task = (
            ShortCircuitOperator(
                dag=dag,
                task_id="check-day-to-skip-execution",
                python_callable=ShortCircuitFunctionEnum.get_function(
                    short_circuit_customization["function"]
                ),
                op_args=["{{ ds }}"],
            )
            if short_circuit_customization
            else None
        )

        create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
            dag=dag,
            task_id="create-cluster",
            cluster_configuration=cluster_params["cluster_config"],
            libraries=cluster_params["default_libraries"],
            access_control_list=cluster_params["access_control_list"],
        )
        terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
            dag=dag, task_id="terminate-cluster"
        )

        dw_task_groups_boundaries = (
            self._get_dw_task_groups_boundaries(dw_task_groups, dw_staging_task_groups)
            if inner_dependencies
            else {}
        )

        self.set_dependencies(
            skip_run_task,
            inner_dependencies,
            task_group,
            create_cluster_task,
            terminate_cluster_task,
            dw_staging_task_groups,
            dw_task_groups,
            dw_task_groups_boundaries,
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

    def _get_dw_task_groups_boundaries(self, dw_task_groups, dw_staging_task_groups):
        dw_task_groups_boundaries = {}
        for table in dw_task_groups:
            initial_tasks = DWTaskGroup.first_tasks(dw_staging_task_groups[table])
            final_tasks = DWTaskGroup.last_tasks(dw_task_groups[table])
            dw_task_groups_boundaries[table] = DWTaskGroup.format_tasks_boundaries(
                initial_tasks=initial_tasks, final_tasks=final_tasks
            )
        return dw_task_groups_boundaries

    def set_dependencies(
        self,
        skip_run_task,
        inner_dependencies,
        task_group,
        create_cluster_task,
        terminate_cluster_task,
        dw_staging_task_groups,
        dw_task_groups,
        dw_task_group_boundaries,
    ):

        if skip_run_task:
            chain(skip_run_task, create_cluster_task)

        if inner_dependencies:
            (
                task_groups_boundaries_without_inner_dependencies,
                inner_dependencies_task_groups_boundaries,
            ) = task_group.set_inner_dag_dependencies(
                task_flow_helper=TaskFlowHelper(),
                task_groups_boundaries=dw_task_group_boundaries,
                dag_inner_dependencies=inner_dependencies,
            )

            create_cluster_task.set_downstream(
                DWTaskGroup.all_first_tasks(
                    task_groups_boundaries_without_inner_dependencies
                )
                + DWTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries)
            )

            terminate_cluster_task.set_upstream(
                DWTaskGroup.all_last_tasks(
                    task_groups_boundaries_without_inner_dependencies
                )
                + DWTaskGroup.last_tasks(inner_dependencies_task_groups_boundaries)
            )

        else:
            create_cluster_task.set_downstream(
                DWTaskGroup.all_first_tasks(dw_staging_task_groups)
            )
            terminate_cluster_task.set_upstream(
                DWTaskGroup.all_last_tasks(dw_task_groups)
            )

        TaskFlowHelper.chain_task_groups_via_common_table(
            dw_staging_task_groups, dw_task_groups
        )

        # Set data quality tasks if exists
        independent_tasks = DWTaskGroup.all_independent_tasks(dw_staging_task_groups)
        if independent_tasks:
            terminate_cluster_task.set_upstream(independent_tasks)
