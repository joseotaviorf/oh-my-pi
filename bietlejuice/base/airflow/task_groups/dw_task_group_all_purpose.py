import json
from datetime import timedelta
from typing import Dict
from os import path

from airflow.utils.helpers import chain
from databricks_plugin import QuintoAndarDatabricksSubmitRunOperator

from bietlejuice.base.airflow.base_task_group import BaseTaskGroup
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import ConfigurationService


class DWTaskGroupAllPurpose(BaseTaskGroup):
    """
    Responsible for creating task groups related to dw operations
    """

    def __init__(
        self,
        dag,
        env,
        dw_bucket,
        dw_schema,
        relative_query_path,
        spark_jobs_path,
        execution_timeout_hours=BaseTaskGroup.DEFAULT_EXECUTION_TIMEOUT_HOURS,
    ):

        super().__init__(
            dag, env, relative_query_path, spark_jobs_path, execution_timeout_hours
        )
        self.dw_bucket = dw_bucket
        self.dw_schema = dw_schema

    def __get_schema(self, table_customization):
        table_schema = table_customization.get("custom_schema", self.dw_schema)
        return table_schema

    def __get_partitions(self, table_customization, partitions):
        table_partitions = table_customization.get("partitions", partitions)
        return table_partitions

    def __get_extra_query_template_params(
        self, table_customization, extra_query_template_params
    ):
        extra_query_template_params = table_customization.get(
            "extra_query_template_params", extra_query_template_params
        )
        return extra_query_template_params

    def __get_extraction_type(self, table_customization, is_incremental):
        table_extraction_type = table_customization.get(
            "extraction_type", "incremental" if is_incremental else "full"
        )
        return table_extraction_type

    def _set_load_task(
        self,
        layer: str,
        schema: str,
        table_name: str,
        extraction_type: str,
        spark_job_extra_args: list,
    ) -> QuintoAndarDatabricksSubmitRunOperator:
        """
        Creates a task that reads an existing SQL query file, executes it inside
        Databricks and writes its resulting dataframe inside the DW bucket, creating or
        updating a table in Databricks Metastore with the same name of the query file.
        """
        load_table_task = QuintoAndarDatabricksSubmitRunOperator(
            databricks_conn_id="databricks_job_cluster",
            dag=self.dag,
            task_id=self.generate_default_task_id(
                task_prefix=self.LOAD_TASK_PREFIX,
                layer=LayerEnum(layer),
                schema=schema,
                table_name=table_name,
            ),
            json={
                "spark_python_task": {
                    "python_file": path.join(
                        self.spark_jobs_path, f"load_{extraction_type}_{layer}.py"
                    ),
                    "parameters": [self.env, self.dw_bucket, schema, table_name]
                    + spark_job_extra_args,
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        return load_table_task

    def _build_metadata_sync_task(
        self,
        schema: str,
        sync_mode: str,
        layer: str,
        table_name: str,
        metadata_file_type: str = None,
    ) -> QuintoAndarDatabricksSubmitRunOperator:
        """
        Creates the task that does 3 things:
            - Sync table structure metadata to Hive
            - Sync table partitions to Hive
            - Sync table lineage and metadata to metadata propagator.
        """
        if layer != LayerEnum.DW.value:
            return
        sync_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
            databricks_conn_id="databricks_job_cluster",
            task_id=self.generate_default_task_id(
                task_prefix=self.SYNC_METADATA_TASK_PREFIX,
                layer=LayerEnum(layer),
                schema=schema,
                table_name=table_name,
            ),
            dag=self.dag,
            json={
                "spark_python_task": {
                    "python_file": path.join(self.spark_jobs_path, "sync_metadata.py"),
                    "parameters": [
                        self.dw_bucket,
                        layer,
                        schema,
                        sync_mode,
                        table_name,
                        metadata_file_type,
                        self.relative_query_path,
                    ],
                }
            },
            execution_timeout=timedelta(minutes=30),
        )

        return sync_metadata_task

    def _set_data_quality_tasks(
        self,
        layer: str,
        table_name: str,
        schema: str,
        tree_path: str = "",
        execution_date="{{ ds }}",
    ) -> list:
        """
        Creates a task to validate data quality rules over the DW Staging table.
        The rules are exclusive for each table, and are expected to be predefined in a
        data quality YAML file named after the very same table.
        """
        data_quality_tasks = []

        if DAGPackagesPathService.artifact_file_exists(
            artifact_type="data_quality",
            dag_name=self.relative_query_path,
            layer=layer,
            table_name=path.join(tree_path, table_name),
        ):
            config_service = ConfigurationService()
            inmetro_bucket = config_service.get_config("inmetro_bucket")

            data_quality_tests_task = QuintoAndarDatabricksSubmitRunOperator(
                databricks_conn_id="databricks_job_cluster",
                dag=self.dag,
                task_id=self.generate_default_task_id(
                    task_prefix=self.DATA_QUALITY_TESTS_TASK_PREFIX,
                    layer=LayerEnum(layer),
                    schema=schema,
                    table_name=table_name,
                ),
                json={
                    "spark_python_task": {
                        "python_file": path.join(
                            self.spark_jobs_path, "data_quality_tests.py"
                        ),
                        "parameters": [
                            self.env,
                            execution_date,
                            inmetro_bucket,
                            layer,
                            self.relative_query_path,
                            table_name,
                            tree_path,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )
            data_quality_tasks = [data_quality_tests_task]

        return data_quality_tasks

    def _set_default_dim_row_task(
        self, layer: str, table_name: str, schema: str, extraction_type: str
    ) -> list:
        """
        Creates a task to insert a default row into the resulting DW Staging table,
        with the surrogate key value of `-1`. This new row is used as a fallback
        value for joins that do not match any dimension attribute and have to return
        a surrogate key to be used as a fact's foreign key.

        # TODO: THIS METHOD SHALL BE MOVED TO THE SPARK DATAFRAME THAT LOADS THE TABLE
        INSTEAD OF KEEPING IT IN A SINGLE SEPARATED SPARK JOB SUBMIT.
        """
        dim_default_row_tasks = []

        if (
            layer == LayerEnum.DW_STAGING.value
            and table_name.startswith("dim_")
            and extraction_type == "full"
        ):
            dim_default_row_task = QuintoAndarDatabricksSubmitRunOperator(
                databricks_conn_id="databricks_job_cluster",
                dag=self.dag,
                task_id=self.generate_default_task_id(
                    task_prefix=self.ADD_DEFAULT_ROW_TASK_PREFIX,
                    layer=LayerEnum(layer),
                    schema=schema,
                    table_name=table_name,
                ),
                json={
                    "spark_python_task": {
                        "python_file": path.join(
                            self.spark_jobs_path, "add_default_row_to_dim.py"
                        ),
                        "parameters": [
                            self.env,
                            self.dw_bucket,
                            schema,
                            layer,
                            table_name,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )
            dim_default_row_tasks.append(dim_default_row_task)

        return dim_default_row_tasks

    def _build_task_group(
        self,
        layer: str,
        table_name: str,
        execution_date="{{ ds }}",
        is_incremental: bool = False,
        partitions: list = None,
        extra_query_template_params: dict = None,
        spark_session_configs: dict = None,
        tree_path: str = "",
        table_customization: Dict[str, Dict[str, str]] = None,
    ) -> dict:

        extra_query_template_params = extra_query_template_params or {}
        spark_session_configs = spark_session_configs or {}
        table_customization = table_customization or {}

        schema = self.__get_schema(table_customization)
        extraction_type = self.__get_extraction_type(
            table_customization, is_incremental
        )
        partitions = self.__get_partitions(table_customization, partitions)
        extra_query_template_params = self.__get_extra_query_template_params(
            table_customization, extra_query_template_params
        )

        incremental_args = (
            ["{{ ds }}", json.dumps(extra_query_template_params)]
            if extraction_type == "incremental"
            else []
        )

        staging_args = (
            [self.relative_query_path, json.dumps(spark_session_configs), tree_path]
            if layer == LayerEnum.DW_STAGING.value
            else []
        )

        load_table_task = self._set_load_task(
            layer=layer,
            schema=schema,
            table_name=table_name,
            extraction_type=extraction_type,
            spark_job_extra_args=[json.dumps(partitions)]
            + incremental_args
            + staging_args,
        )

        metadata_task = self._build_metadata_sync_task(
            schema=schema,
            sync_mode=self.SINGLE_TABLE,
            layer=layer,
            table_name=table_name,
            metadata_file_type=MetadataTypeEnum.LINEAGE.value,
        )

        data_quality_tasks = self._set_data_quality_tasks(
            layer=layer,
            table_name=table_name,
            schema=schema,
            tree_path=tree_path,
            execution_date=execution_date,
        )

        default_dim_row_tasks = self._set_default_dim_row_task(
            layer=layer,
            table_name=table_name,
            schema=schema,
            extraction_type=extraction_type,
        )

        if metadata_task:
            chain(load_table_task, metadata_task)
        chain(load_table_task, *default_dim_row_tasks, *data_quality_tasks)

        final_tasks = (
            default_dim_row_tasks or [metadata_task]
            if metadata_task
            else [] or [load_table_task]
        )

        return self.format_tasks_boundaries(
            initial_tasks=[load_table_task],
            final_tasks=final_tasks,
            independent_tasks=data_quality_tasks,
        )

    def build_dw_task_group(
        self,
        table_name: str,
        spectrum_iam_role: str = None,
        execution_date="{{ ds }}",
        is_incremental: bool = False,
        partitions: list = None,
        extra_query_template_params: dict = None,
        spark_session_configs: dict = None,
        tree_path: str = "",
        has_load_to_redshift_task: bool = True,
        table_customization: Dict[str, Dict[str, str]] = None,
    ) -> dict:

        return self._build_task_group(
            layer=LayerEnum.DW.value,
            table_name=table_name,
            execution_date=execution_date,
            is_incremental=is_incremental,
            partitions=partitions,
            extra_query_template_params=extra_query_template_params,
            spark_session_configs=spark_session_configs,
            tree_path=tree_path,
            table_customization=table_customization,
        )

    def build_dw_staging_task_group(
        self,
        table_name: str,
        spectrum_iam_role: str = None,
        execution_date="{{ ds }}",
        is_incremental: bool = False,
        partitions: list = None,
        extra_query_template_params: dict = None,
        spark_session_configs: dict = None,
        tree_path: str = "",
        has_load_to_redshift_task: bool = True,
        table_customization: Dict[str, Dict[str, str]] = None,
    ) -> dict:

        return self._build_task_group(
            layer=LayerEnum.DW_STAGING.value,
            table_name=table_name,
            execution_date=execution_date,
            is_incremental=is_incremental,
            partitions=partitions,
            extra_query_template_params=extra_query_template_params,
            spark_session_configs=spark_session_configs,
            tree_path=tree_path,
            table_customization=table_customization,
        )
