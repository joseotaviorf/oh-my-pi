import os
from airflow.models import DAG
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.enums.task_enum import TaskEnum
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.airflow.task_creators.task_creator_factory import (
    TaskCreatorFactory,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class RawCDCWorkflow(BaseWorkflow):
    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args)
        self.env = os.environ.get("ENVIRONMENT")

    def build_dag(self):
        dag = super().dag_instance()

        # Parameters
        dag_execution_context = self._get_dag_execution_context(dag)
        self._initialize_task_creators(dag_execution_context)

        tables_customization = self.workflow_args["tables_customization"]

        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()

        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )

        for raw_table_name, table_parameters in tables_customization.items():
            raw_initial_task, raw_final_task = self._create_raw_tasks(
                table_name=raw_table_name,
                dummy_terminate_job_cluster_task=dummy_terminate_job_cluster_task,
            )
            clean_initial_task, clean_final_task = self._create_clean_tasks(
                table_name=table_parameters.get("clean_table_name", raw_table_name),
                table_customization=table_parameters,
                dummy_terminate_job_cluster_task=dummy_terminate_job_cluster_task,
            )
            execute_job_cluster_task >> raw_initial_task
            raw_final_task >> clean_initial_task
            clean_final_task >> dummy_terminate_job_cluster_task

        return dag

    def _get_dag_execution_context(self, dag: DAG) -> DagExecutionContext:
        bucket = self.config_service.get_config("datalake_bucket")
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
        )

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER, self.config_service
        )
        self.load_transactional_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CDC_TRANSACTIONAL
        )
        self.load_cdc_raw_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CDC_RAW
        )
        self.load_cdc_clean_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CDC_CLEAN
        )
        self.sync_hive_structure_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SYNC_HIVE_STRUCTURE
        )
        self.sync_hive_partitions_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SYNC_HIVE_PARTITIONS
        )
        self.dummy_job_cluster_finished_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DUMMY_JOB_CLUSTER_FINISHED
        )
        self.propagate_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.PROPAGATE_METADATA
        )
        self.data_quality_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )

    def _should_propagate_metadata(self, table_attributes: TableAttributes) -> bool:
        """
        Check if propagate metadata task should be added into the Workflow.
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

    def _create_raw_tasks(self, table_name: str, dummy_terminate_job_cluster_task):
        """
        Creates raw tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.
        """
        transactional_table_attributes = TableAttributes(
            self.dag_args, self.workflow_args, LayerEnum.TRANSACTIONAL, table_name
        )

        load_cdc_transactional_task = self.load_transactional_task_creator.create_task(
            transactional_table_attributes
        )

        raw_table_attributes = TableAttributes.from_attributes(
            transactional_table_attributes, layer=LayerEnum.RAW
        )

        load_raw_task = self.load_cdc_raw_task_creator.create_task(raw_table_attributes)

        if self._has_data_quality_tests(raw_table_attributes):
            data_quality_tests_raw_task = self.data_quality_task_creator.create_task(
                raw_table_attributes
            )
            load_raw_task >> data_quality_tests_raw_task >> dummy_terminate_job_cluster_task

        sync_metastore_structure_raw_task = self.sync_hive_structure_task_creator.create_task(
            raw_table_attributes
        )

        sync_metastore_partitions_raw_task = self.sync_hive_partitions_task_creator.create_task(
            raw_table_attributes
        )

        load_cdc_transactional_task >> load_raw_task >> sync_metastore_structure_raw_task >> sync_metastore_partitions_raw_task

        if self._should_propagate_metadata(raw_table_attributes):
            propagate_table_lineage_raw_task = self.propagate_metadata_task_creator.create_task(
                raw_table_attributes
            )
            sync_metastore_partitions_raw_task >> propagate_table_lineage_raw_task >> dummy_terminate_job_cluster_task
        else:
            sync_metastore_partitions_raw_task >> dummy_terminate_job_cluster_task

        return load_cdc_transactional_task, load_raw_task

    def _create_clean_tasks(
        self,
        table_name: str,
        table_customization: dict,
        dummy_terminate_job_cluster_task,
    ):
        """
        Creates clean tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.
        """
        clean_table_attributes = TableAttributes(
            self.dag_args,
            self.workflow_args,
            LayerEnum.CLEAN,
            table_name,
            table_customization,
        )

        load_clean_task = self.load_cdc_clean_task_creator.create_task(
            clean_table_attributes
        )

        sync_metastore_structure_clean_task = self.sync_hive_structure_task_creator.create_task(
            clean_table_attributes
        )

        sync_metastore_partitions_clean_task = self.sync_hive_partitions_task_creator.create_task(
            clean_table_attributes
        )

        propagate_table_metadata_clean_task = self.propagate_metadata_task_creator.create_task(
            clean_table_attributes
        )

        load_clean_task >> sync_metastore_structure_clean_task >> sync_metastore_partitions_clean_task >> propagate_table_metadata_clean_task

        if self._has_data_quality_tests(clean_table_attributes):
            data_quality_tests_clean_task = self.data_quality_task_creator.create_task(
                clean_table_attributes
            )
            load_clean_task >> data_quality_tests_clean_task >> dummy_terminate_job_cluster_task

        return load_clean_task, propagate_table_metadata_clean_task
