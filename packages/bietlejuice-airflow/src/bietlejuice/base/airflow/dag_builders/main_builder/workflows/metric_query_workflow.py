from airflow.operators.dummy_operator import DummyOperator

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.job_cluster_engine import (
    attach_emr_job_cluster_finished_work_prerequisites,
    attach_emr_terminate_cluster_work_prerequisites,
    get_job_cluster_completion_sink,
)
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
    DEFAULT_DATABRICKS_CONN_ID = "databricks_default"

    def build_dag(self):
        tables_customization = self.workflow_args.get("tables_customization", {})
        default_partitions = self.workflow_args.get("default_partitions")
        default_is_incremental = (
            self.workflow_args.get("default_extraction_type") == "incremental"
        )
        inner_dependencies = self.workflow_args.get("inner_dependencies")
        extra_query_template_params = self.workflow_args.get(
            "extra_query_template_params"
        )

        metrics_bucket = self.config_service.get_config("metrics_bucket")
        databricks_bietlejuice_repo_path = self.config_service.get_config(
            "databricks_bietlejuice_repo_path"
        )
        base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
        business_unit = self.dag_name.split(self.BUSINESS_DOMAIN_DELIMITER)[0]
        source_database_base_name = business_unit.replace("metric_", "")
        target_database_base_name = source_database_base_name

        dag = self.dag_instance()
        self.cluster_args.setdefault(
            "databricks_conn_id", self.DEFAULT_DATABRICKS_CONN_ID
        )

        dag_execution_context = self._get_dag_execution_context(
            dag,
            metrics_bucket,
            databricks_submission_mode="task_submission",
        )
        engine = dag_execution_context.job_cluster_engine

        create_cluster_task = engine.create_execute_cluster_task(
            config_service=self.config_service,
            minimum_cluster_runtime_version=None,
            execute_job_cluster_local_id=None,
        )

        task_group = DatalakeTaskGroup(
            is_validation=self.is_validation,
            dag=dag,
            env=self.env,
            datalake_bucket=metrics_bucket,
            relative_query_path=self.dag_name,
            spark_jobs_path=base_spark_jobs_path,
            databricks_conn_id=dag_execution_context.databricks_conn_id,
            job_cluster_engine=engine,
            dag_args=self.dag_args,
            workflow_args=self.workflow_args,
        )

        metric_task_group = task_group.build_task_group_from_sql_files(
            layer=LayerEnum.METRIC,
            source_database_base_name=source_database_base_name,
            target_database_base_name=target_database_base_name,
            tables_customization=tables_customization,
            partitions=default_partitions,
            is_incremental=default_is_incremental,
            extra_query_template_params=extra_query_template_params,
        )

        job_cluster_finished_task = None
        if dag_execution_context.use_airflow_emr:
            job_cluster_finished_task = DummyOperator(
                task_id="job-cluster-finished", dag=dag
            )
            terminate_cluster_task = get_job_cluster_completion_sink(
                dag_execution_context,
                create_cluster_task,
                job_cluster_finished_task,
            )
        else:
            terminate_cluster_task = engine.create_databricks_terminate_cluster_task()

        self.set_dependencies(
            inner_dependencies,
            task_group,
            create_cluster_task,
            terminate_cluster_task,
            metric_task_group,
        )

        if dag_execution_context.use_airflow_emr:
            attach_emr_terminate_cluster_work_prerequisites(
                dag_execution_context,
                terminate_cluster_task,
                execute_job_cluster_task=create_cluster_task,
                job_cluster_finished_task=job_cluster_finished_task,
            )
            attach_emr_job_cluster_finished_work_prerequisites(
                dag_execution_context,
                job_cluster_finished_task,
                cluster_completion_sink=terminate_cluster_task,
            )

        DatasetAdder.attach_reprocessing_guard(create_cluster_task)

        return dag

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
