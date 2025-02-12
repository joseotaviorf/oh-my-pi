import os
from datetime import datetime
import re
from typing import Tuple

from airflow import DAG
from pendulum import timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.builder_interface import (
    BuilderInterface,
)
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback


class BaseWorkflow(BuilderInterface):
    def __init__(self, dag_args, workflow_args, cluster_args) -> None:
        """
        This class must be a component that all workflows must inherit to have the dag instance.
        :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
        :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
        :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
        """
        super().__init__()
        self.env = os.environ.get("ENVIRONMENT")

        self.dag_args = dag_args
        self.dag_name = self.dag_args["name"]
        self.dag_id = f"bietlejuice.{self.dag_name}"
        self.config_service = ConfigurationService(self.dag_name)

        self.workflow_args = workflow_args
        self.cluster_args = cluster_args

        self.local_tz = timezone("America/Sao_Paulo")

    def get_date_param(self, dag_run, default_date, date_param_name) -> str:
        """Macro to get date parameter from dag_run conf. If not found, returns default_date."""

        date_param = dag_run.conf.get(date_param_name) if dag_run.conf else None
        if date_param and re.match(r"[0-9]{4}\-[0-9]{2}\-[0-9]{2}", date_param):
            return date_param
        return default_date

    def dag_instance(self, **kwargs):
        schedule_start_date = self._get_start_date()
        doc_md = self._get_dag_documentation()
        user_defined_macros = {"get_date_param": self.get_date_param}
        user_defined_macros.update(kwargs.get("user_defined_macros", {}))
        opsgenie_callback = OpsgenieCallback()

        dag = DAG(
            dag_id=self.dag_id,
            catchup=self.dag_args.get("catchup", False),
            default_args={
                "owner": self.dag_args["owner"],
                "wait_for_downstream": False,
                "depends_on_past": False,
                "on_failure_callback": opsgenie_callback.task_failure_alert,
            },
            start_date=schedule_start_date,
            schedule_interval=self.dag_args.get("schedule_interval", None),
            doc_md=doc_md,
            user_defined_macros=user_defined_macros,
            **kwargs,
        )

        return dag

    def _get_start_date(self):
        start_date_from_yml = self.dag_args.get("schedule_start_date", "2023,1,1")
        start_date_from_yml = start_date_from_yml.split(",")
        schedule_start_date = datetime(
            year=int(start_date_from_yml[0]),
            month=int(start_date_from_yml[1]),
            day=int(start_date_from_yml[2]),
            tzinfo=self.local_tz,
        )

        return schedule_start_date

    def _get_dag_documentation(self):
        dag_documentation = self.dag_args.get("documentation")
        doc_md_chart_url = self.config_service.get_config("doc_md_chart_url")

        if dag_documentation:
            doc_md = BaseDAG.generate_doc_md_str(
                dag_name=self.dag_name,
                doc_md_chart_url=doc_md_chart_url,
                dag_documentation=dag_documentation,
                dag_owner=self.dag_args["owner"],
            )
        else:
            doc_md = BaseDAG.get_dag_doc(self.dag_name).format(
                chart_url=doc_md_chart_url, dag_id=self.dag_id
            )

        return doc_md

    def _get_dag_execution_context(
        self, dag: DAG, bucket: str, **kwargs
    ) -> DagExecutionContext:
        databricks_bietlejuice_repo_path = self.config_service.get_config(
            "databricks_bietlejuice_repo_path"
        )
        base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
        return DagExecutionContext(
            dag,
            self.env,
            bucket,
            base_spark_jobs_path,
            self.dag_args,
            self.workflow_args,
            self.cluster_args,
            **kwargs,
        )

    def _initialize_load_start_and_end_date(self) -> Tuple[str, str]:
        """
        Reads load start and end dates from the workflow args and sets them as template params.
        Returns the start and end dates as strings.
        """

        if "extra_query_template_params" not in self.workflow_args:
            self.workflow_args["extra_query_template_params"] = {}

        load_start_date = self.workflow_args["extra_query_template_params"].get(
            "load_start_date", "{{ get_date_param(dag_run, ds, 'load_start_date') }}"
        )
        load_end_date = self.workflow_args["extra_query_template_params"].get(
            "load_end_date", "{{ get_date_param(dag_run, ds, 'load_end_date') }}"
        )

        self.workflow_args["extra_query_template_params"][
            "load_start_date"
        ] = load_start_date
        self.workflow_args["extra_query_template_params"][
            "load_end_date"
        ] = load_end_date

        return load_start_date, load_end_date

    def _set_inner_dependencies(
        self,
        table_first_tasks: dict,
        table_last_tasks: dict,
        previous_task_if_no_dependencies=None,
        next_task_if_no_dependents=None,
    ) -> None:
        """
        Sets the inner dependencies between the tables, based on the inner_dependencies dictionary. It is not
        case sensitive. All the dependencies (values in the list) must finish before the dependent (key of the dictionary) starts.
        table_first_tasks: dictionary with the first task of each table. The key is the table name.
        table_last_tasks: dictionary with the last task of each table. The key is the table name.
        previous_task_if_no_dependencies: task that will be set as the previous task if the table\
        has no dependencies. Usually, this will be the cluster starting task.
        next_task_if_no_dependents: task that will be set as the next task if the table has no dependents.\
        Usually, this will be the cluster ending task.
        """
        inner_dependencies = self._get_lowercase_inner_dependencies()
        tables_with_dependents = set()
        for table_name, dependent_first_task in table_first_tasks.items():
            if table_name.lower() in inner_dependencies:
                self._link_dependencies_to_dependent(
                    table_last_tasks,
                    inner_dependencies[table_name.lower()],
                    dependent_first_task,
                    tables_with_dependents,
                )
            elif previous_task_if_no_dependencies:
                previous_task_if_no_dependencies >> dependent_first_task

        if next_task_if_no_dependents:
            self._link_tables_without_dependents_to_end_task(
                table_last_tasks, tables_with_dependents, next_task_if_no_dependents
            )

    def _get_lowercase_inner_dependencies(self):
        """Returns the inner dependencies dictionary from the workflow args, both with the key and values in lowercase"""

        inner_dependencies_case_sensitive = self.workflow_args.get(
            "inner_dependencies", {}
        )
        inner_dependencies_lowercase = {}
        for table_name, dependencies_list in inner_dependencies_case_sensitive.items():
            inner_dependencies_lowercase[table_name.lower()] = [
                dep.lower() for dep in dependencies_list
            ]
        return inner_dependencies_lowercase

    def _link_dependencies_to_dependent(
        self,
        table_last_tasks: dict,
        dependencies: list,
        dependent_first_task,
        tables_with_dependents: set,
    ) -> None:
        """Links the last task of each dependency to the first task of the dependent. Also adds the dependency to the set of tables with dependents."""

        for inner_dependency in dependencies:
            if inner_dependency not in table_last_tasks:
                raise ValueError(
                    f"Error finding table '{inner_dependency}' during inner dependencies settings. "
                    "Make sure this table is named correctly and its query exists."
                )
            table_last_tasks[inner_dependency] >> dependent_first_task
            tables_with_dependents.add(inner_dependency)

    def _link_tables_without_dependents_to_end_task(
        self, table_last_tasks: dict, tables_with_dependents: set, end_task
    ) -> None:
        """
        Links the tables without dependents (i.e., tables without any task after them) to the end task.
        """
        for table_name, table_task in table_last_tasks.items():
            if table_name not in tables_with_dependents:
                table_task >> end_task

    def _check_include_data_quality_task(
        self, table_attributes: TableAttributes
    ) -> bool:
        """
        Checks if data quality tests task should be added into the workflow
        by verifying if its file exists for the provided table.
        """
        return DAGPackagesPathService.artifact_file_exists(
            artifact_type="data_quality",
            dag_name=self.dag_name,
            layer=table_attributes.layer.value,
            table_name=table_attributes.table_name,
        )

    def _check_include_propagate_metadata_task(
        self, table_attributes: TableAttributes
    ) -> bool:
        """
        Checks if propagate metadata task should be added into the workflow.
        """

        has_product_database_name = (
            "lineage_product_database_name" in self.workflow_args
        )
        if table_attributes.layer == LayerEnum.RAW and has_product_database_name:
            return True

        return DAGPackagesPathService.artifact_file_exists(
            artifact_type="metadata",
            dag_name=self.dag_name,
            layer=table_attributes.layer.value,
            table_name=table_attributes.table_name,
        )

    def _check_include_sync_hive_tasks(self, table_attributes: TableAttributes) -> bool:
        """
        Checks if sync hive structure task should be added into the workflow.
        """
        default_has_hive_sync = self.workflow_args.get("has_hive_sync", True)
        return table_attributes.table_customization.get(
            "has_hive_sync", default_has_hive_sync
        )

    def _check_include_skip_run_task(self) -> bool:
        """
        Checks if short circuit operator (skip run) task should be added into the workflow.
        This method is used to check if the skip run task should be placed before the execute-job-cluster task.
        """

        return "short_circuit_customization" in self.workflow_args

    def _check_include_get_table_metrics_task(self, tables_customization: dict) -> bool:
        if self.workflow_args["database_type"] not in ("postgres", "mysql"):
            return False
        for table_parameters in tables_customization.values():
            if "get_table_metrics" in table_parameters:
                return True
        return False

    # TODO: Rethink our abstractions. This method is only here because it's used in multiple workflows, but it's a little strange to have it here.
    def _create_generate_metrics_task_group(
        self, generate_table_metrics_task_creator, sync_metadata_task_creator
    ) -> Tuple:
        """
        Creates the generate table metrics task, sets the dependencies between the tasks and returns the first and last task of the group.
        """
        clean_metrics_table_attributes = TableAttributes(
            self.dag_args,
            self.workflow_args,
            LayerEnum.CLEAN,
            "table_ingestion_metrics",
            table_customization={"custom_schema": "data_quality_ingestion_metrics"},
        )

        sync_metadata = sync_metadata_task_creator.create_task(
            clean_metrics_table_attributes
        )

        get_table_metrics_task = generate_table_metrics_task_creator.create_task(
            clean_metrics_table_attributes
        )

        get_table_metrics_task >> sync_metadata

        return get_table_metrics_task, sync_metadata
