from typing import List

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


class RawAPIIngestionWorkflow(BaseWorkflow):
    """
    Workflow for ingesting data from REST APIs.

    This workflow supports both `raw_inner_dependencies` (preferred for raw-layer control)
    and `inner_dependencies` (backward compatibility with other workflows) for configuring
    task execution order within the raw layer. The `raw_inner_dependencies` parameter takes
    precedence if both are present in the workflow configuration.
    """

    MAX_TABLES_PER_CLUSTER = 20

    def build_dag(self):
        """
        Builds the DAG for API ingestion workflow.

        Returns:
            DAG: The configured Airflow DAG object
        """
        dag = super().dag_instance()

        bucket_config = self.workflow_args.get("bucket_config_name", "datalake_bucket")
        bucket = self.config_service.get_config(bucket_config)
        load_start_date, load_end_date = self._initialize_load_start_and_end_date()

        self._set_default_spark_job_config()

        dag_execution_context = self._get_dag_execution_context(
            dag, bucket, load_start_date=load_start_date, load_end_date=load_end_date
        )

        self._initialize_task_creators(dag_execution_context)

        tables_customization = self.workflow_args["tables_customization"]

        all_raw_tables = self._get_raw_tables()
        all_clean_tables = self._get_clean_tables(all_raw_tables)

        self._create_all_tasks(all_raw_tables, all_clean_tables, tables_customization)

        return dag

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        """
        Initialize all task creators needed for the API ingestion workflow.

        Args:
            dag_execution_context: The DAG execution context
        """
        task_creator_factory = TaskCreatorFactory(dag_execution_context)

        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER,
            self.config_service,
            minimum_databricks_version="16.4",
        )

        self.load_raw_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_API_RAW
        )

        self.load_clean_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_DELTA
        )

        self.optimize_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.OPTIMIZE_DELTA_TABLE
        )

        self.data_quality_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.DATA_QUALITY_TESTS, self.config_service
        )

        self.register_delta_table_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.REGISTER_DELTA_TABLE
        )

        self.sync_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SYNC_METADATA
        )

        self.dummy_job_cluster_finished_task_creator = (
            task_creator_factory.get_task_creator(TaskEnum.DUMMY_JOB_CLUSTER_FINISHED)
        )

    def _set_default_spark_job_config(self):
        """
        Sets default Spark job configuration if not provided in workflow_args.

        This method ensures that load_spark_job, spark_job_prefix, and spark_job_arguments
        have appropriate defaults for the api_ingestion workflow, similar to how gsheets
        workflow handles its Spark job configuration.

        The default ``spark_job_arguments`` list is kept for declaration consistency and readers of
        the YAML only; the API raw load path uses ``LoadAPIRawTaskCreator``, which builds the Spark
        job argument list in code via ``_get_parameters`` and does not consume this template.
        """
        if not self.workflow_args.get("load_spark_job"):
            self.workflow_args["load_spark_job"] = "load_api_ingestion_raw"

        if not self.workflow_args.get("spark_job_prefix"):
            self.workflow_args["spark_job_prefix"] = "base"

        if not self.workflow_args.get("spark_job_arguments"):
            self.workflow_args["spark_job_arguments"] = [
                "{environment}",
                "{bucket}",
                "{dag_name}",
                "{table_name}",
                "{{ data_interval_start | ds }}",
                "{partitions}",
                "{extraction_type}",
                "{load_start_date}",
                "{load_end_date}",
            ]

    def _get_raw_tables(self) -> List[TableAttributes]:
        """
        Returns the table attributes for all tables to be ingested from the API.

        Returns:
            List[TableAttributes]: List of table attributes for the raw layer
        """
        return [
            TableAttributes(
                self.dag_args, self.workflow_args, LayerEnum.RAW, table_name
            )
            for table_name in self.workflow_args["tables_customization"]
        ]

    def _get_clean_tables(
        self, raw_tables: List[TableAttributes]
    ) -> List[TableAttributes]:
        """
        Returns the table attributes for all tables in the clean layer.
        Only returns tables that actually have clean layer queries defined.

        Args:
            raw_tables: List of raw table attributes

        Returns:
            List[TableAttributes]: List of table attributes for the clean layer
        """
        clean_table_names_in_dag = set(
            DAGPackagesPathService.list_queries_files_in_composer(
                dag_name=self.dag_name, layer=LayerEnum.CLEAN.value
            )
        )

        clean_tables = []
        for table in raw_tables:
            clean_table_name = table.table_customization.get(
                "clean_table_name", table.table_name
            ).lower()
            if clean_table_name in clean_table_names_in_dag:
                clean_tables.append(
                    TableAttributes.from_attributes(
                        table, layer=LayerEnum.CLEAN, table_name=clean_table_name
                    )
                )
        return clean_tables

    def _create_all_tasks(
        self,
        all_raw_tables: List[TableAttributes],
        all_clean_tables: List[TableAttributes],
        tables_customization: dict,
    ):
        """
        Creates all tasks for the API ingestion workflow.

        This method will:
        1. Create execute job cluster tasks
        2. Create load raw tasks for each API endpoint/table
        3. Create load clean tasks
        4. Create optimize delta table tasks
        5. Set up task dependencies

        Args:
            all_raw_tables: List of raw table attributes
            all_clean_tables: List of clean table attributes
            tables_customization: Dictionary with table-specific customizations
        """
        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()
        dag_final_tasks = self._set_dag_final_tasks()

        if all_clean_tables:
            optimize_clean_task = self.optimize_delta_table_task_creator.create_task(
                all_clean_tables
            )
            optimize_clean_task >> dag_final_tasks
        else:
            optimize_clean_task = dag_final_tasks

        clean_table_map = {
            table.table_name.lower(): table for table in all_clean_tables
        }

        raw_first_tasks = {}
        raw_last_tasks = {}
        clean_first_tasks = {}
        clean_last_tasks = {}

        for raw_table in all_raw_tables:
            clean_table_name = raw_table.table_customization.get(
                "clean_table_name", raw_table.table_name
            ).lower()
            clean_table = clean_table_map.get(clean_table_name)

            raw_initial_task, raw_final_task = self._create_raw_tasks(
                raw_table, dag_final_tasks=dag_final_tasks
            )
            execute_job_cluster_task >> raw_initial_task
            raw_first_tasks[raw_table.table_name] = raw_initial_task
            raw_last_tasks[raw_table.table_name] = raw_final_task

            if clean_table:
                clean_initial_task, clean_final_task = self._create_clean_tasks(
                    clean_table, optimize_clean_task, dag_final_tasks=dag_final_tasks
                )
                raw_final_task >> clean_initial_task
                clean_final_task >> dag_final_tasks
                clean_first_tasks[clean_table.table_name] = clean_initial_task
                clean_last_tasks[clean_table.table_name] = clean_final_task
            else:
                raw_final_task >> dag_final_tasks

        if raw_first_tasks and raw_last_tasks:
            raw_inner_dependencies_key = (
                "raw_inner_dependencies"
                if "raw_inner_dependencies" in self.workflow_args
                else "inner_dependencies"
            )
            self._set_inner_dependencies(
                table_first_tasks=raw_first_tasks,
                table_last_tasks=raw_last_tasks,
                previous_task_if_no_dependencies=execute_job_cluster_task,
                next_task_if_no_dependents=dag_final_tasks,
                inner_dependencies_key=raw_inner_dependencies_key,
            )

        if clean_first_tasks and clean_last_tasks:
            self._set_inner_dependencies(
                table_first_tasks=clean_first_tasks,
                table_last_tasks=clean_last_tasks,
                next_task_if_no_dependents=dag_final_tasks,
                inner_dependencies_key="clean_inner_dependencies",
            )

    def _set_dag_final_tasks(self):
        """
        Creates and returns the final tasks of the DAG.

        This method creates the dummy task that signals the job cluster has finished
        processing all tables. This task is used as the final dependency for all
        table-specific tasks to ensure proper task orchestration.

        Returns:
            BaseOperator: The dummy job cluster finished task that serves as the
                         final dependency point for all table tasks
        """
        dummy_terminate_job_cluster_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )
        return dummy_terminate_job_cluster_task

    def _create_raw_tasks(self, raw_table_attributes: TableAttributes, dag_final_tasks):
        """
        Creates raw tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.

        This method creates the load raw task using LOAD_API_RAW task creator, which will
        execute the reusable load_api_ingestion_raw Spark job. The table name is converted
        to lowercase for most tasks to avoid Hive naming issues, except for the load task
        which uses the original table name. The method also conditionally creates sync metadata
        and data quality tasks based on workflow configuration.

        Note: Raw tables do NOT get optimize tasks (only delta/clean tables do).

        Args:
            raw_table_attributes: TableAttributes instance for the raw table
            dag_final_tasks: The final task(s) of the DAG to chain dependencies

        Returns:
            Tuple: A tuple containing (first_task, last_task) where both are the load_raw_task
                   in this case since it's the only task created directly
        """
        raw_table_attributes_lower = TableAttributes.from_attributes(
            raw_table_attributes, table_name=raw_table_attributes.table_name.lower()
        )

        load_raw_task = self.load_raw_task_creator.create_task(raw_table_attributes)

        if self._check_include_sync_hive_tasks(raw_table_attributes_lower):
            if self._check_include_propagate_metadata_task(raw_table_attributes):
                propagate_table_lineage_raw_task = (
                    self.sync_metadata_task_creator.create_task(
                        raw_table_attributes, "--bypass-hive"
                    )
                )
                (load_raw_task >> propagate_table_lineage_raw_task >> dag_final_tasks)
            else:
                load_raw_task >> dag_final_tasks

        if self._check_include_data_quality_task(raw_table_attributes_lower):
            data_quality_tests_raw_task = self.data_quality_task_creator.create_task(
                raw_table_attributes_lower
            )
            (load_raw_task >> data_quality_tests_raw_task >> dag_final_tasks)

        return load_raw_task, load_raw_task

    def _create_clean_tasks(
        self,
        clean_table_attributes: TableAttributes,
        optimize_clean_task,
        dag_final_tasks,
    ):
        """
        Creates clean tasks, sets their internal dependencies and returns the first
        and the last tasks of the dependency flow.

        This method creates the load clean task using LOAD_DELTA task creator, which
        executes the SQL query defined for the clean layer table. It also conditionally
        creates register delta table, sync metadata, and data quality tasks based on
        workflow configuration. All tasks are properly chained with dependencies.

        Args:
            clean_table_attributes: TableAttributes instance for the clean table
            optimize_clean_task: The optimize delta table task for clean layer to chain dependencies
            dag_final_tasks: The final task(s) of the DAG to chain dependencies

        Returns:
            Tuple: A tuple containing (first_task, last_task) where first_task is the
                   load_clean_task and last_task may be sync_metadata_clean_task if
                   hive sync is enabled, otherwise load_clean_task
        """
        load_clean_task = self.load_clean_task_creator.create_task(
            clean_table_attributes
        )
        load_clean_task >> optimize_clean_task
        last_clean_task = load_clean_task

        if self._check_include_sync_hive_tasks(clean_table_attributes):
            register_delta_table_clean_task = (
                self.register_delta_table_task_creator.create_task(
                    clean_table_attributes
                )
            )

            sync_metadata_clean_task = self.sync_metadata_task_creator.create_task(
                clean_table_attributes, "--bypass-hive"
            )
            last_clean_task = sync_metadata_clean_task

            (
                load_clean_task
                >> register_delta_table_clean_task
                >> sync_metadata_clean_task
            )

        if self._check_include_data_quality_task(clean_table_attributes):
            data_quality_tests_clean_task = self.data_quality_task_creator.create_task(
                clean_table_attributes
            )
            (load_clean_task >> data_quality_tests_clean_task >> dag_final_tasks)

        return load_clean_task, last_clean_task
