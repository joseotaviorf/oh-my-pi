import os
from typing import List, Tuple
from airflow.models import DAG
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.task_creators.task_creator_factory import (
    TaskCreatorFactory,
    TaskEnum,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class EnrichQueryWorkflow(BaseWorkflow):
    """
    Inherits the dag build base to define the flow that creates tasks from sql files, in the enrich Layer.
    :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
    :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
    :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
    """

    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args)
        self.env = os.environ.get("ENVIRONMENT")

    def build_dag(self):
        dag = self.dag_instance()

        self.dag_execution_context = self._get_execution_context(dag)
        tables = self._get_tables()
        self._initialize_task_creators()

        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()
        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )

        table_first_tasks = {}
        table_last_tasks = {}
        for table in tables:
            (
                table_first_tasks[table.table_name],
                table_last_tasks[table.table_name],
            ) = self._create_enrich_tasks(table)

        self._set_dependencies(
            execute_job_cluster_task,
            table_first_tasks,
            table_last_tasks,
            dummy_terminate_job_cluster_task,
        )

        return dag

    def _get_execution_context(self, dag: DAG) -> DagExecutionContext:
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

    def _get_tables(self) -> List[TableAttributes]:
        """Returns the table attributes for all the tables in the enrich layer."""

        table_names = DAGPackagesPathService.list_queries_files_in_composer(
            dag_name=self.dag_name, layer=LayerEnum.ENRICH.value
        )
        return [
            TableAttributes(
                self.dag_args, self.workflow_args, LayerEnum.ENRICH, table_name
            )
            for table_name in table_names
        ]

    def _create_enrich_tasks(self, table: TableAttributes) -> Tuple:
        """Returns a tuple with the first (Load) and last (Propagate Metadata) tasks of the table."""

        load = self.load_enrich_task_creator.create_task(table)
        sync_metastore_structure = self.sync_hive_structure_task_creator.create_task(
            table
        )
        sync_metastore_partitions = self.sync_hive_partitions_task_creator.create_task(
            table
        )
        propagate_metadata = self.propagate_metadata_task_creator.create_task(table)
        load >> sync_metastore_structure >> sync_metastore_partitions >> propagate_metadata

        if self._has_data_quality_tests(table):
            data_quality = self.data_quality_tests_task_creator.create_task(table)
            load >> data_quality

        return load, propagate_metadata

    def _set_dependencies(
        self,
        execute_job_cluster_task,
        table_first_tasks: dict,
        table_last_tasks: dict,
        job_cluster_finished_task,
    ) -> None:
        inner_dependencies = self.workflow_args.get("inner_dependencies")

        if inner_dependencies:
            # TODO: Implement inner dependencies here
            raise NotImplementedError(
                "Inner dependencies are not implemented yet for enrich layer"
            )
        else:
            execute_job_cluster_task >> table_first_tasks.values()

        job_cluster_finished_task << table_last_tasks.values()

    def _initialize_task_creators(self):
        task_creator_factory = TaskCreatorFactory(self.dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER, self.config_service
        )
        self.load_enrich_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_QUERY
        )
        self.data_quality_tests_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )
        self.propagate_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.PROPAGATE_METADATA
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
