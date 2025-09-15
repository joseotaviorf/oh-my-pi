import math
from typing import Tuple, List
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


class RawCustomIngestionWorkflow(BaseWorkflow):
    """
    This workflow is responsible for creating dags for raw ingestions that use custom
    sparkjobs to load data from API's or databases
    """

    MAX_TABLES_PER_CLUSTER = 14

    def build_dag(self):
        dag = super().dag_instance()

        bucket_config = self.workflow_args.get("bucket_config_name", "datalake_bucket")
        bucket = self.config_service.get_config(bucket_config)
        load_start_date, load_end_date = self._initialize_load_start_and_end_date()
        self.dag_execution_context = self._get_dag_execution_context(
            dag, bucket, load_start_date=load_start_date, load_end_date=load_end_date
        )
        self._initialize_task_creators(self.dag_execution_context)

        first_tasks_of_dag = self._create_all_tasks_in_clusters()

        if self._check_include_skip_run_task():
            skip_run_task = self.skip_run_task_creator.create_task()
            skip_run_task >> first_tasks_of_dag

        return dag

    def _get_tables(self) -> List[TableAttributes]:
        """Returns the table attributes for all the tables in the clean layer."""

        table_names = DAGPackagesPathService.list_queries_files_in_composer(
            dag_name=self.dag_name, layer=LayerEnum.CLEAN.value
        )
        return [
            TableAttributes(
                self.dag_args, self.workflow_args, LayerEnum.CLEAN, table_name
            )
            for table_name in table_names
        ]

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)
        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_databricks_version="12.2",
        )
        self.load_custom_ingestion_raw_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_CUSTOM
        )
        self.load_query_clean_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_DELTA
        )
        self.sync_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SYNC_METADATA
        )
        self.dummy_job_cluster_finished_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DUMMY_JOB_CLUSTER_FINISHED
        )
        self.register_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.REGISTER_DELTA_TABLE
        )
        self.optimize_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.OPTIMIZE_DELTA_TABLE
        )
        self.data_quality_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )
        self.skip_run_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SKIP_RUN
        )

    def _create_all_tasks_in_clusters(self) -> List:
        """
        Creates all the tasks for the workflow, and sets their internal dependencies
        """
        tables_customization = self.workflow_args["tables_customization"]
        table_names = sorted(list(tables_customization.keys()))

        n_tables = len(table_names)
        if n_tables == 0:
            return []

        n_clusters = math.ceil(n_tables / self.MAX_TABLES_PER_CLUSTER)
        tables_per_cluster = math.ceil(n_tables / n_clusters)

        first_tasks_of_dag = []
        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )

        for i in range(0, n_tables, tables_per_cluster):
            cluster_table_names = table_names[i : i + tables_per_cluster]
            cluster_tables_customization = {
                name: tables_customization[name] for name in cluster_table_names
            }
            execute_job_cluster_local_id = (i // tables_per_cluster) + 1

            execute_job_cluster_task = self._create_tasks_for_cluster(
                cluster_tables_customization,
                execute_job_cluster_local_id,
                dummy_terminate_job_cluster_task,
            )
            first_tasks_of_dag.append(execute_job_cluster_task)

        return first_tasks_of_dag

    def _create_tasks_for_cluster(
        self,
        tables_customization_cluster: dict,
        execute_job_cluster_local_id: int,
        dummy_terminate_job_cluster_task,
    ):
        """
        Creates all the tasks for a specific cluster and sets their dependencies.
        """
        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task(
            execute_job_cluster_local_id if execute_job_cluster_local_id > 1 else None
        )

        clean_tables_in_dag = self._get_tables()
        clean_table_names_in_dag = {t.table_name for t in clean_tables_in_dag}

        cluster_clean_tables = []
        for raw_name, params in tables_customization_cluster.items():
            clean_name = params.get("clean_table_name", raw_name).lower()
            if clean_name in clean_table_names_in_dag:
                cluster_clean_tables.append(
                    TableAttributes(
                        self.dag_args,
                        self.workflow_args,
                        LayerEnum.CLEAN,
                        clean_name,
                        params,
                    )
                )

        if cluster_clean_tables:
            optimize_delta_tables_task = self.optimize_delta_table_task_creator.create_task(
                cluster_clean_tables,
                optimize_delta_table_local_id=execute_job_cluster_local_id,
            )
            optimize_delta_tables_task >> dummy_terminate_job_cluster_task
        else:
            optimize_delta_tables_task = dummy_terminate_job_cluster_task

        raw_first_tasks = {}
        raw_last_tasks = {}
        clean_first_tasks = {}
        clean_last_tasks = {}

        (
            tables_customization_raw_dependency,
            tables_customization_without_raw_dependency,
        ) = self._generate_filtered_tables_customizations(tables_customization_cluster)

        # Raw tasks and their clean dependencies
        for (
            raw_table_name,
            table_parameters,
        ) in tables_customization_without_raw_dependency.items():
            raw_initial_task, raw_final_task = self._create_raw_tasks(
                table_name=raw_table_name, last_task=dummy_terminate_job_cluster_task
            )

            raw_first_tasks[raw_table_name.lower()] = raw_initial_task
            raw_last_tasks[raw_table_name.lower()] = raw_final_task
            execute_job_cluster_task >> raw_initial_task

            clean_table_name = table_parameters.get(
                "clean_table_name", raw_table_name
            ).lower()
            if clean_table_name in clean_table_names_in_dag:
                clean_initial_task, clean_final_task = self._create_clean_tasks(
                    table_name=clean_table_name,
                    table_customization=table_parameters,
                    optimize_delta_tables_task=optimize_delta_tables_task,
                )
                raw_final_task >> clean_initial_task
                clean_first_tasks[clean_table_name] = clean_initial_task
                clean_last_tasks[clean_table_name] = clean_final_task

        self._set_inner_dependencies(
            table_first_tasks=raw_first_tasks,
            table_last_tasks=raw_last_tasks,
            inner_dependencies_key="raw_inner_dependencies",
        )

        # Clean tasks with explicit raw dependency
        for (
            table_name,
            table_parameters,
        ) in tables_customization_raw_dependency.items():
            raw_table_dependency = table_parameters.get("raw_table_dependency").lower()
            clean_table_name = table_parameters.get(
                "clean_table_name", table_name
            ).lower()

            if clean_table_name in clean_table_names_in_dag:
                clean_initial_task, clean_final_task = self._create_clean_tasks(
                    table_name=clean_table_name,
                    table_customization=table_parameters,
                    optimize_delta_tables_task=optimize_delta_tables_task,
                )

                if raw_table_dependency in raw_last_tasks:
                    raw_last_tasks[raw_table_dependency] >> clean_initial_task
                # If the dependency is not in the cluster, _set_inner_dependencies will fail,
                # which is the expected behavior for an incorrect configuration.

                clean_first_tasks[clean_table_name] = clean_initial_task
                clean_last_tasks[clean_table_name] = clean_final_task

        self._set_inner_dependencies(
            clean_first_tasks,
            clean_last_tasks,
            next_task_if_no_dependents=optimize_delta_tables_task,
            inner_dependencies_key="clean_inner_dependencies",
        )

        return execute_job_cluster_task

    def _create_raw_tasks(self, table_name: str, last_task) -> Tuple:
        """
        Creates raw tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.
        """
        raw_table_attributes = TableAttributes(
            self.dag_args,
            self.workflow_args,
            LayerEnum.RAW,
            table_name.lower(),  # The table name must be lower case for most of the tasks, to avoid problems with Hive
        )

        load_raw_task = self.load_custom_ingestion_raw_task_creator.create_task(
            TableAttributes.from_attributes(
                raw_table_attributes,
                table_name=table_name,  # The exception is the load task, which must have the original table name, for it to be found in the source
            )
        )

        if self._check_include_sync_hive_tasks(raw_table_attributes):
            if self._check_include_propagate_metadata_task(raw_table_attributes):
                sync_metadata = self.sync_metadata_task_creator.create_task(
                    raw_table_attributes
                )
            else:
                sync_metadata = self.sync_metadata_task_creator.create_task(
                    raw_table_attributes, "--bypass-propagate"
                )
            (load_raw_task >> sync_metadata >> last_task)

        if self._check_include_data_quality_task(raw_table_attributes):
            data_quality_tests_raw_task = self.data_quality_task_creator.create_task(
                raw_table_attributes
            )
            (load_raw_task >> data_quality_tests_raw_task >> last_task)

        return load_raw_task, load_raw_task

    def _create_clean_tasks(
        self, table_name: str, table_customization: dict, optimize_delta_tables_task
    ) -> Tuple:
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

        load_clean_task = self.load_query_clean_task_creator.create_task(
            clean_table_attributes
        )

        if self._check_include_sync_hive_tasks(clean_table_attributes):
            register_table = self.register_delta_table_task_creator.create_task(
                clean_table_attributes
            )
            sync_metadata = self.sync_metadata_task_creator.create_task(
                clean_table_attributes, "--bypass-hive"
            )
            (
                load_clean_task
                >> register_table
                >> sync_metadata
                >> optimize_delta_tables_task
            )
        if self._check_include_data_quality_task(clean_table_attributes):
            data_quality = self.data_quality_task_creator.create_task(
                clean_table_attributes
            )
            load_clean_task >> data_quality >> optimize_delta_tables_task
        return load_clean_task, load_clean_task

    def _generate_filtered_tables_customizations(self, tables_customization: dict):
        """
        Filters the tables that have the raw_table_dependency parameter in the tables_customization,
        returning two dictionaries, one with the tables that contain the parameter and another with the remaining tables.
        """
        tables_customization_with_raw_dependency = {}
        tables_customization_without_raw_dependency = tables_customization.copy()

        for table_name, table_parameters in tables_customization.items():
            raw_table_dependency = table_parameters.get("raw_table_dependency")
            if raw_table_dependency:
                if (
                    raw_table_dependency
                    not in tables_customization_without_raw_dependency
                ):
                    raise ValueError(
                        f"Error finding table '{raw_table_dependency}' during raw table dependencies settings. "
                        "Make sure this table is named correctly and its table declaration exists."
                    )

                tables_customization_with_raw_dependency[
                    table_name
                ] = tables_customization.get(table_name)
                del tables_customization_without_raw_dependency[table_name]

        return (
            tables_customization_with_raw_dependency,
            tables_customization_without_raw_dependency,
        )
