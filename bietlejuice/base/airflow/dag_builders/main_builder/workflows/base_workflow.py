import os
from datetime import datetime
import re

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

        dag = DAG(
            dag_id=self.dag_id,
            catchup=self.dag_args.get("catchup", False),
            default_args={
                "owner": self.dag_args["owner"],
                "wait_for_downstream": False,
                "depends_on_past": False,
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
