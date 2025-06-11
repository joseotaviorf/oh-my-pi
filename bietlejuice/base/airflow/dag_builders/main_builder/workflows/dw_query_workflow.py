from airflow.operators.python_operator import ShortCircuitOperator
from airflow.utils.helpers import chain

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.task_creator_factory import (
    TaskCreatorFactory,
    TaskEnum,
)
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
        extra_query_template_params = self.workflow_args.get(
            "extra_query_template_params"
        )
        spark_session_configs = self.workflow_args.get("spark_session_configs", {})
        inner_dependencies = self.workflow_args.get("inner_dependencies")

        dw_bucket = self.config_service.get_config("dw_bucket")
        dag = self.dag_instance()
        dag_execution_context = self._get_dag_execution_context(dag, dw_bucket)
        self._initialize_task_creators(dag_execution_context)

        databricks_bietlejuice_repo_path = self.config_service.get_config(
            "databricks_bietlejuice_repo_path"
        )
        base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"

        task_group = DWTaskGroup(
            dag=dag,
            env=self.env,
            dw_bucket=dw_bucket,
            dw_schema=dw_schema,
            relative_query_path=self.dag_name,
            spark_jobs_path=base_spark_jobs_path,
            databricks_conn_id=dag_execution_context.databricks_conn_id,
        )

        dw_staging_task_groups = task_group.build_task_group_from_sql_files(
            layer=LayerEnum.DW_STAGING,
            spark_session_configs=spark_session_configs,
            tables_customization=tables_customization,
            partitions=default_partitions,
            is_incremental=default_is_incremental,
            extra_query_template_params=extra_query_template_params,
        )

        dw_task_groups = task_group.build_task_group_from_sql_files(
            layer=LayerEnum.DW,
            tables_customization=tables_customization,
            partitions=default_partitions,
            is_incremental=default_is_incremental,
            has_load_to_redshift_task=has_load_to_redshift_task,
            extra_query_template_params=extra_query_template_params,
        )

        skip_run_task = (
            ShortCircuitOperator(
                dag=dag,
                task_id="check-day-to-skip-execution",
                python_callable=ShortCircuitFunctionEnum.get_function(
                    short_circuit_customization["function"]
                ),
                op_args=["{{ data_interval_start | ds }}"],
            )
            if short_circuit_customization
            else None
        )

        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()
        job_cluster_finished_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
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
            execute_job_cluster_task,
            dw_staging_task_groups,
            dw_task_groups,
            dw_task_groups_boundaries,
            job_cluster_finished_task,
        )

        return dag

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER, self.config_service
        )
        self.dummy_job_cluster_finished_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DUMMY_JOB_CLUSTER_FINISHED
        )

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
        execute_job_cluster_task,
        dw_staging_task_groups,
        dw_task_groups,
        dw_task_groups_boundaries,
        job_cluster_finished_task,
    ):
        if skip_run_task:
            chain(skip_run_task, execute_job_cluster_task)

        if inner_dependencies:
            (
                task_groups_boundaries_without_inner_dependencies,
                inner_dependencies_task_groups_boundaries,
            ) = task_group.set_inner_dag_dependencies(
                task_flow_helper=TaskFlowHelper(),
                task_groups_boundaries=dw_task_groups_boundaries,
                dag_inner_dependencies=inner_dependencies,
            )

            execute_job_cluster_task.set_downstream(
                DWTaskGroup.all_first_tasks(
                    task_groups_boundaries_without_inner_dependencies
                )
                + DWTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries)
            )

        else:
            execute_job_cluster_task.set_downstream(
                DWTaskGroup.all_first_tasks(dw_staging_task_groups)
            )

        TaskFlowHelper.chain_task_groups_via_common_table(
            dw_staging_task_groups, dw_task_groups
        )

        job_cluster_finished_task.set_upstream(
            DWTaskGroup.all_last_tasks(dw_task_groups)
        )
