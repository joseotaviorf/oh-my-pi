import json
from datetime import timedelta
from os import path
from typing import Dict, Optional, Set

from airflow.models.baseoperator import BaseOperator
from airflow.utils.helpers import chain
from databricks_plugin import QuintoAndarDatabricksSubmitRunOperator

from bietlejuice.base.airflow.base_task_group import BaseTaskGroup
from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.airflow.validation_aware import validation_spark_extra_args
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.service.dag_packages_path_service import (
    DAGPackagesPathService,
    DataQualityLayerCache,
)
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.dag_metadata_service import DAGMetadataService

AIRFLOW_DEFAULT_POOL = "default_pool"  # TODO: Add to parameter service to be created


class DatalakeTaskGroup(BaseTaskGroup):
    """
    Responsible for creating task groups related to datalake operations
    """

    def __init__(
        self,
        dag,
        env,
        datalake_bucket,
        relative_query_path,
        spark_jobs_path,
        athena_query_result_location=None,
        execution_timeout_hours=BaseTaskGroup.DEFAULT_EXECUTION_TIMEOUT_HOURS,
        databricks_conn_id="databricks_default",
        default_table_privileges=None,
        is_validation: bool = False,
        job_cluster_engine=None,
        dag_args: Optional[dict] = None,
        workflow_args: Optional[dict] = None,
    ):
        """
        :param dag: main dag instance
        :type dag: airflow.models.DAG
        :param env: forno or prod environments
        :type env: str
        :param datalake_bucket: datalake bucket in S3
        :type datalake_bucket: str
        :param relative_query_path: relative query path from default queries
            path containing sql file for the table to be created
        :type relative_query_path: str
        :param spark_jobs_path: base path for spark jobs
        :type spark_jobs_path: str
        :param execution_timeout_hours: timeout in hours to be set to the tasks
        :type execution_timeout_hours: int
        """
        super().__init__(
            dag, env, relative_query_path, spark_jobs_path, execution_timeout_hours
        )
        self.datalake_bucket = datalake_bucket

        config_service = ConfigurationService()
        self.inmetro_bucket = config_service.get_config("inmetro_bucket")
        self.databricks_conn_id = databricks_conn_id
        self.default_table_privileges = default_table_privileges
        self.is_validation = is_validation
        self.job_cluster_engine = job_cluster_engine
        self.dag_args = dag_args
        self.workflow_args = workflow_args
        self._config_services: Dict[str, ConfigurationService] = {}
        self._metadata_tables_cache: Dict[str, Set[str]] = {}
        self._dq_cache = DataQualityLayerCache(self.relative_query_path)
        self._has_any_metadata_cache: Optional[bool] = None

    def _get_config_service(self, source: str) -> ConfigurationService:
        """Return cached ConfigurationService for source, creating on first use."""
        if source not in self._config_services:
            self._config_services[source] = ConfigurationService(source)
        return self._config_services[source]

    def _get_metadata_tables(self, layer: str) -> Set[str]:
        """Return cached set of table paths with metadata, loading once per layer."""
        if layer not in self._metadata_tables_cache:
            self._metadata_tables_cache[layer] = (
                DAGMetadataService.list_metadata_table_paths(
                    self.relative_query_path, layer
                )
            )
        return self._metadata_tables_cache[layer]

    def _has_any_metadata(self) -> bool:
        """Return cached result of whether DAG has any metadata files."""
        if self._has_any_metadata_cache is None:
            self._has_any_metadata_cache = bool(
                DAGMetadataService.get_all_dag_metadata_files(self.relative_query_path)
            )
        return self._has_any_metadata_cache

    def _get_data_quality_tables(self, layer: str) -> Set[str]:
        """Return cached set of table paths with data quality files, loading once per layer."""
        return self._dq_cache.get(layer)

    def _metadata_task_spark_conf(self) -> Optional[dict]:
        if (
            self.job_cluster_engine is not None
            and self.job_cluster_engine.uses_emr_terminate_after_optimize
        ):
            from bietlejuice.base.airflow.job_cluster_engine import (
                METADATA_TASK_LIGHTWEIGHT_SPARK_CONF,
            )

            return METADATA_TASK_LIGHTWEIGHT_SPARK_CONF
        return None

    def _build_load_task(
        self,
        task_id: str,
        extraction_spark_job_file: str,
        do_output_xcom_push: bool,
        pool: str = AIRFLOW_DEFAULT_POOL,
        spark_job_extra_args: list = [],
    ) -> BaseOperator:
        job_parameters = [self.env, self.datalake_bucket] + spark_job_extra_args
        if self.job_cluster_engine is not None:
            load_table_task = self.job_cluster_engine.create_spark_python_task(
                spark_job_path=extraction_spark_job_file,
                task_id=task_id,
                job_parameters=job_parameters,
                execution_timeout_hours=self.execution_timeout_hours,
                pool=pool if pool != AIRFLOW_DEFAULT_POOL else None,
                do_output_xcom_push=do_output_xcom_push,
            )
        else:
            load_table_task = QuintoAndarDatabricksSubmitRunOperator(
                task_id=task_id,
                pool=pool,
                dag=self.dag,
                json={
                    "spark_python_task": {
                        "python_file": extraction_spark_job_file,
                        "parameters": job_parameters,
                    }
                },
                do_output_xcom_push=do_output_xcom_push,
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
                databricks_conn_id=self.databricks_conn_id,
            )
        if not self.is_validation:
            DatasetAdder.attach_dataset_to_task(load_table_task)

        return load_table_task

    def _build_metadata_sync_task(
        self,
        source: str,
        sync_mode: str,
        layer: str,
        database_name: str,
        table_name: str,
        metadata_file_type: str = None,
        bypass: str = "",
    ) -> BaseOperator:
        config_service = self._get_config_service(source)
        product_db_name = ""
        if "lineage_product_database_name" in config_service.configs:
            product_db_name = config_service.get_config("lineage_product_database_name")

        if not metadata_file_type:
            has_metadata = (
                self._has_any_metadata()
                if sync_mode == self.ALL_TABLES
                else table_name in self._get_metadata_tables(layer)
            )
            if has_metadata:
                metadata_file_type = MetadataTypeEnum.TAGS.value
            elif product_db_name:
                metadata_file_type = MetadataTypeEnum.FULL_CONTENT_LINEAGE.value
            else:
                metadata_file_type = ""
                bypass += " --bypass-propagate"
        raw_params = (
            ["--product-database-name", product_db_name]
            if layer == LayerEnum.RAW.value and product_db_name
            else []
        )
        task_id = self.generate_default_task_id(
            task_prefix=self.SYNC_METADATA_TASK_PREFIX,
            layer=LayerEnum(layer),
            schema=source,
            table_name=table_name,
        )
        type_args = (
            ["--metadata-type", metadata_file_type] if metadata_file_type else []
        )
        sync_parameters = (
            [
                self.datalake_bucket,
                layer,
                database_name,
                sync_mode,
            ]
            + ([table_name] if table_name else [True])
            + type_args
            + [self.relative_query_path]
            + raw_params
            + bypass.split()
        )
        sync_job_path = path.join(self.spark_jobs_path, "sync_metadata.py")
        if self.job_cluster_engine is not None:
            return self.job_cluster_engine.create_spark_python_task(
                spark_job_path=sync_job_path,
                task_id=task_id,
                job_parameters=sync_parameters,
                execution_timeout_hours=0.5,
                task_spark_conf=self._metadata_task_spark_conf(),
            )

        sync_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
            task_id=task_id,
            dag=self.dag,
            json={
                "spark_python_task": {
                    "python_file": sync_job_path,
                    "parameters": sync_parameters,
                }
            },
            execution_timeout=timedelta(minutes=30),
            databricks_conn_id=self.databricks_conn_id,
        )

        return sync_metadata_task

    def _build_data_quality_tasks(
        self,
        layer: str,
        sync_mode: str,
        table_name: str,
        source: str = None,
        tree_path: str = "",
        execution_date="{{ data_interval_start | ds }}",
        criticality: str = None,
    ) -> list:
        data_quality_tasks = []

        lookup_key = path.normpath(path.join(tree_path, table_name))
        if (
            sync_mode == self.SINGLE_TABLE
            and lookup_key in self._get_data_quality_tables(layer)
        ):
            tables_names = [table_name]

        elif sync_mode == self.ALL_TABLES:
            tables_names = (
                DAGPackagesPathService.list_data_quality_tests_files_in_composer(
                    dag_name=self.relative_query_path, layer=layer
                )
            )
        else:
            return data_quality_tasks

        for table in tables_names:
            dq_task_id = self.generate_default_task_id(
                task_prefix=self.DATA_QUALITY_TESTS_TASK_PREFIX,
                layer=LayerEnum(layer),
                schema=source,
                table_name=table_name,
            )
            dq_parameters = [
                self.env,
                execution_date,
                self.inmetro_bucket,
                layer,
                self.relative_query_path,
                table,
                tree_path,
            ]
            dq_job_path = path.join(self.spark_jobs_path, "data_quality_tests.py")
            if self.job_cluster_engine is not None:
                data_quality_task = self.job_cluster_engine.create_spark_python_task(
                    spark_job_path=dq_job_path,
                    task_id=dq_task_id,
                    job_parameters=dq_parameters,
                    execution_timeout_hours=self.execution_timeout_hours,
                    task_spark_conf=self._metadata_task_spark_conf(),
                )
            else:
                data_quality_task = QuintoAndarDatabricksSubmitRunOperator(
                    dag=self.dag,
                    task_id=dq_task_id,
                    json={
                        "spark_python_task": {
                            "python_file": dq_job_path,
                            "parameters": dq_parameters,
                        }
                    },
                    execution_timeout=timedelta(hours=self.execution_timeout_hours),
                    databricks_conn_id=self.databricks_conn_id,
                )

            if criticality:
                data_quality_task.params.update({"criticality": criticality})
            data_quality_tasks.append(data_quality_task)

        return data_quality_tasks

    def _build_raw_task_group(
        self,
        source,
        database_name,
        extraction_spark_job_file,
        execution_date="{{ data_interval_start | ds }}",
        table_name="",
        raw_spark_job_extra_args=None,
        pool=AIRFLOW_DEFAULT_POOL,
        has_hive_sync=True,
        tree_path="",
        do_output_xcom_push=False,
    ):
        """
        Create a task group containing 2 tasks:
        1. load to raw from source
        2. sync metadata from spark metastore to hive metastore

        :param source: source name
        :type source: str
        :param database_name: database in which the data will be written
        :type database_name: str
        :param extraction_spark_job_file: full filepath for the extraction spark job
        :type extraction_spark_job_file: str
        :param execution_date: job execution date. Defaults to the start of the data interval  {{ data_interval_start | ds }}
        :type execution_date: str
        :param table_name: the table name when loading a single table
        :type table_name: str
        :param raw_spark_job_extra_args: extra arguments to be passed to the spark job,
            default spark job parameters are [env, bucket]
        :type raw_spark_job_extra_args: list[str]
        :param pool: airflow's pool name
        :type pool: str
        :param has_hive_sync: if this table is going to have Hive sync
        :param tree_path: partial path used in some DAGs off of our pattern
        :param do_output_xcom_push: flag indicating if the job result should be pushed into xcom.
        :return: initial and final tasks of the created task group
        :rtype: dict
        """

        layer_enum = LayerEnum.RAW
        layer = layer_enum.value
        sync_mode = self.SINGLE_TABLE if table_name else self.ALL_TABLES

        if self.is_validation:
            raw_spark_job_extra_args = list(raw_spark_job_extra_args or [])
            raw_spark_job_extra_args.extend(
                validation_spark_extra_args(True, LayerEnum.RAW, source, table_name)
            )

        load_table_task = self._build_load_task(
            pool=pool,
            task_id=self.generate_default_task_id(
                task_prefix=self.LOAD_TASK_PREFIX,
                layer=layer_enum,
                schema=source,
                table_name=table_name,
            ),
            extraction_spark_job_file=extraction_spark_job_file,
            spark_job_extra_args=raw_spark_job_extra_args or [],
            do_output_xcom_push=do_output_xcom_push,
        )
        load_table_task.params.update(
            {
                "schema": database_name,
                "table_name": table_name,
                "layer": layer,
                "bucket": self.datalake_bucket,
                "storage_format": StorageFormatEnum.JSON.value,
            }
        )

        if not self.is_validation:
            sync_metadata_task = self._build_metadata_sync_task(
                source=source,
                sync_mode=sync_mode,
                layer=layer,
                database_name=database_name,
                table_name=table_name,
                bypass="" if has_hive_sync else "--bypass-hive",
            )
            chain(load_table_task, sync_metadata_task)
            raw_final_tasks = [load_table_task, sync_metadata_task]
        else:
            raw_final_tasks = [load_table_task]

        quality_tasks = self._build_data_quality_tasks(
            layer=layer,
            sync_mode=sync_mode,
            table_name=table_name,
            source=source,
            tree_path=tree_path,
            execution_date=execution_date,
        )

        load_table_task.set_downstream(quality_tasks)

        return self.format_tasks_boundaries(
            initial_tasks=[load_table_task],
            final_tasks=raw_final_tasks,
            independent_tasks=quality_tasks,
            load_chain_tasks=[load_table_task],
        )

    def _build_task_group(
        self,
        layer,
        source_database_base_name,
        target_database_base_name,
        table_name,
        partitions=None,
        is_incremental=False,
        spark_session_configs=None,
        extra_query_template_params=None,
        schema="",  # TODO: Remove schema param after dags are all in pattern
        # 'schema' parameter could be replaced by source or target database_base_name.
        # However, since we have out of pattern paths in our project directory we
        # cannot chose only one now, we would need a refactoring first.
        tree_path="",
        execution_date="{{ data_interval_start | ds }}",
        has_hive_sync=True,
        table_customization=None,
        do_output_xcom_push=False,
    ):
        """
        Create a task group containing 2 tasks:
        1. load table to metastore database using a sql query
        2. sync table metadata from spark metastore to hive metastore + propagate to metadata-propagator service
        Extra optional tasks:
        3. data-quality tests to validate from YAML definition
        :param layer: layer Enum
        :type layer: bietlejuice.base.pipeline.LayerEnum member
        :param source_database_base_name: database base name for the source
            table database
        :type source_database_base_name: str
        :param target_database_base_name database base name for the target
            table database
        :type target_database_base_name: str
        :param table_name: table name to be created
        :type table_name: str
        :param partitions: list of columns to partition table
        :type partitions: list[str]
        :param is_incremental: if this table uses incremental load type
        :type is_incremental: bool
        :param spark_session_configs: custom config parameters to be set in spark session
        :type spark_session_configs: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :param execution_date: job execution date. Defaults to the start of the data interval {{ data_interval_start | ds }}
        :type execution_date: str
        :param has_hive_sync: if this table is going to have Hive sync
        :param table_customization: table's structure customization, when applicable
        :param do_output_xcom_push: flag indicating if the job result should be pushed into xcom.
        :return: dict with initial and final tasks of the created task group
        :rtype: dict
        """

        layer_enum = layer
        layer = layer_enum.value
        partitions = partitions or []
        table_customization = table_customization or {}
        criticality = None
        if self.dag_args is not None and self.workflow_args is not None:
            criticality = TableAttributes(
                self.dag_args,
                self.workflow_args,
                layer_enum,
                table_name,
                table_customization,
            ).criticality
        spark_session_configs = spark_session_configs or {}
        extra_query_template_params = extra_query_template_params or {}
        table_extraction_type = "incremental" if is_incremental else "full"

        extraction_spark_job_file = table_customization.get(
            "extraction_spark_job_file"
        ) or path.join(self.spark_jobs_path, f"load_table_{table_extraction_type}.py")
        table_privileges = (
            table_customization.get("table_privileges") or self.default_table_privileges
        )
        spark_job_extra_args = [
            layer,
            source_database_base_name,
            target_database_base_name,
            self.relative_query_path,
            table_name,
            str(partitions),
            execution_date,
            json.dumps(spark_session_configs),
            str(extra_query_template_params),
            schema,
            tree_path,
        ]
        spark_job_extra_args.extend(
            validation_spark_extra_args(
                self.is_validation, layer_enum, target_database_base_name, table_name
            )
        )
        spark_job_extra_args.extend(
            ["--table-privileges", json.dumps(table_privileges)]
        )

        load_table_task = self._build_load_task(
            task_id=self.generate_default_task_id(
                task_prefix=self.LOAD_TASK_PREFIX,
                layer=layer_enum,
                schema=source_database_base_name,
                table_name=table_name,
            ),
            extraction_spark_job_file=extraction_spark_job_file,
            do_output_xcom_push=do_output_xcom_push,
            spark_job_extra_args=spark_job_extra_args,
        )
        load_table_task.params.update(
            {
                "schema": source_database_base_name,
                "table_name": table_name,
                "layer": layer,
                "bucket": self.datalake_bucket,
                "storage_format": StorageFormatEnum.PARQUET.value,
                **({"criticality": criticality} if criticality else {}),
            }
        )

        if not self.is_validation:
            metadata_sync_task = self._build_metadata_sync_task(
                source=source_database_base_name,
                sync_mode=self.SINGLE_TABLE,
                layer=layer,
                database_name=target_database_base_name,
                table_name=table_name,
                metadata_file_type=MetadataTypeEnum.LINEAGE.value,
                bypass="" if has_hive_sync else "--bypass-hive",
            )
            chain(load_table_task, metadata_sync_task)
            sql_final_tasks = [load_table_task, metadata_sync_task]
        else:
            sql_final_tasks = [load_table_task]

        quality_tasks = []
        lookup_key = path.normpath(path.join(tree_path, table_name))
        if lookup_key in self._get_data_quality_tables(layer):
            quality_tasks = self._build_data_quality_tasks(
                layer=layer,
                sync_mode=self.SINGLE_TABLE,
                table_name=table_name,
                tree_path=tree_path,
                execution_date=execution_date,
                criticality=criticality,
            )

            load_table_task.set_downstream(quality_tasks)

        return self.format_tasks_boundaries(
            initial_tasks=[load_table_task],
            final_tasks=sql_final_tasks,
            independent_tasks=quality_tasks,
            load_chain_tasks=[load_table_task],
        )

    def build_raw_task_group_for_single_table(
        self,
        source,
        target_database_base_name,
        table_name,
        extraction_spark_job_file,
        raw_spark_job_extra_args=None,
        pool=AIRFLOW_DEFAULT_POOL,
        has_hive_sync=True,
        tree_path="",
        do_output_xcom_push=False,
    ):
        """
        Build a task group for raw layer to extract a specific table from source

        :param source: source name
        :type source: str
        :param target_database_base_name: database base name for the target
            table database
        :type target_database_base_name: str
        :param table_name: table name to be extracted and synced
        :type table_name: str
        :param extraction_spark_job_file: full filepath for the extraction spark job
        :type extraction_spark_job_file: str
        :param raw_spark_job_extra_args: extra arguments to be passed to the spark job,
            default spark job parameters are [env, bucket]
        :type raw_spark_job_extra_args: list[str]
        :param pool: airflow's pool name
        :type pool: str
        :param has_hive_sync: if this table is going to have Hive sync
        :param tree_path: partial path used in some DAGs off of our pattern
        :param do_output_xcom_push: flag indicating if the job result should be pushed into xcom.
        :return: initial and final tasks of the created task group
        :rtype: dict
        """
        return self._build_raw_task_group(
            source=source,
            database_name=target_database_base_name,
            extraction_spark_job_file=extraction_spark_job_file,
            table_name=table_name,
            raw_spark_job_extra_args=raw_spark_job_extra_args,
            pool=pool,
            has_hive_sync=has_hive_sync,
            tree_path=tree_path,
            do_output_xcom_push=do_output_xcom_push,
        )

    def build_raw_task_group_for_all_tables(
        self,
        source,
        target_database_base_name,
        extraction_spark_job_file,
        raw_spark_job_extra_args=None,
        pool=AIRFLOW_DEFAULT_POOL,
        has_hive_sync=True,
    ):
        """
        Build a task group for raw layer to extract all tables from source

        :param source: source name
        :type source: str
        :param target_database_base_name: database base name for the target
            table database
        :type target_database_base_name: str
        :param extraction_spark_job_file: full filepath for the extraction spark job
        :type extraction_spark_job_file: str
        :param raw_spark_job_extra_args: extra arguments to be passed to the spark job,
            default spark job parameters are [env, bucket]
        :type raw_spark_job_extra_args: list[str]
        :param pool: airflow's pool name
        :type pool: str
        :param has_hive_sync: if this table is going to have Hive sync
        :return: initial and final tasks of the created task group
        :rtype: dict
        """
        return self._build_raw_task_group(
            source=source,
            database_name=target_database_base_name,
            extraction_spark_job_file=extraction_spark_job_file,
            raw_spark_job_extra_args=raw_spark_job_extra_args,
            pool=pool,
            has_hive_sync=has_hive_sync,
        )

    def build_clean_task_group(
        self,
        source_database_base_name,
        target_database_base_name,
        table_name,
        partitions=None,
        is_incremental=False,
        has_create_external_table_task=False,
        spark_session_configs=None,
        extra_query_template_params=None,
        schema="",
        tree_path="",
        execution_date="{{ data_interval_start | ds }}",
        has_hive_sync=True,
        table_customization: Dict[str, Dict[str, str]] = None,
        do_output_xcom_push=False,
    ):
        """
        Build a task group for clean layer

        :param source_database_base_name: database base name for the source
            table database
        :type source_database_base_name: str
        :param target_database_base_name database base name for the target
            table database
        :type target_database_base_name: str
        :param table_name: table name to be created
        :type table_name: str
        :param partitions: list of columns to partition table
        :type partitions: list[str]
        :param is_incremental: if this table uses incremental load type
        :type is_incremental: bool
        :param has_create_external_table_task: # TODO: scheduled for removal
        :param spark_session_configs: custom config parameters to be set in spark session
        :type spark_session_configs: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :param execution_date: job execution date. Defaults to the start of the data interval {{ data_interval_start | ds }}
        :param has_hive_sync: if this table is going to have Hive sync
        :param table_customization: table's structure customization, when applicable
        :param do_output_xcom_push: flag indicating if the job result should be pushed into xcom.
        :type execution_date: str
        :rtype: list[BaseOperator]
        """

        return self._build_task_group(
            LayerEnum.CLEAN,
            source_database_base_name,
            target_database_base_name,
            table_name,
            partitions,
            is_incremental,
            spark_session_configs,
            extra_query_template_params,
            schema,
            tree_path,
            execution_date,
            has_hive_sync,
            table_customization,
            do_output_xcom_push,
        )

    def build_enrich_task_group(
        self,
        source_database_base_name,
        target_database_base_name,
        table_name,
        partitions=None,
        is_incremental=False,
        has_create_external_table_task=False,
        spark_session_configs=None,
        extra_query_template_params=None,
        schema="",
        execution_date="{{ data_interval_start | ds }}",
        has_hive_sync=True,
        table_customization: Dict[str, Dict[str, str]] = None,
        do_output_xcom_push=False,
    ):
        """
        Build a task group for enrich layer

        :param source_database_base_name: database base name for the source
            table database
        :type source_database_base_name: str
        :param target_database_base_name database base name for the target
            table database
        :type target_database_base_name: str
        :param table_name: table name to be created
        :type table_name: str
        :param partitions: list of columns to partition table
        :type partitions: list[str]
        :param is_incremental: if this table uses incremental load type
        :type is_incremental: bool
        :param has_create_external_table_task: # TODO: scheduled for removal
        :param spark_session_configs: custom config parameters to be set in spark session
        :type spark_session_configs: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :param execution_date: job execution date. Defaults to the start of the data interval {{ data_interval_start | ds }}
        :param has_hive_sync: if this table is going to have Hive sync
        :param table_customization: table's structure customization, when applicable
        :param do_output_xcom_push: flag indicating if the job result should be pushed into xcom.
        :type execution_date: str
        :rtype: list[BaseOperator]
        """
        return self._build_task_group(
            LayerEnum.ENRICH,
            source_database_base_name,
            target_database_base_name,
            table_name,
            partitions,
            is_incremental,
            spark_session_configs,
            extra_query_template_params,
            schema,
            execution_date=execution_date,
            has_hive_sync=has_hive_sync,
            table_customization=table_customization,
            do_output_xcom_push=do_output_xcom_push,
        )

    def build_metric_task_group(
        self,
        source_database_base_name,
        target_database_base_name,
        table_name,
        partitions=None,
        is_incremental=False,
        has_create_external_table_task=False,
        spark_session_configs=None,
        extra_query_template_params=None,
        schema="",
        execution_date="{{ data_interval_start | ds }}",
        has_hive_sync=True,
        table_customization: Dict[str, Dict[str, str]] = None,
        do_output_xcom_push=False,
    ):
        """
        Build a task group for metric layer

        :param source_database_base_name: database base name for the source
            table database
        :type source_database_base_name: str
        :param target_database_base_name database base name for the target
            table database
        :type target_database_base_name: str
        :param table_name: table name to be created
        :type table_name: str
        :param partitions: list of columns to partition table
        :type partitions: list[str]
        :param is_incremental: if this table uses incremental load type
        :type is_incremental: bool
        :param has_create_external_table_task: # TODO: scheduled for removal
        :param spark_session_configs: custom config parameters to be set in spark session
        :type spark_session_configs: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :param execution_date: job execution date. Defaults to the start of the data interval {{ data_interval_start | ds }}
        :param has_hive_sync: if this table is going to have Hive sync
        :param table_customization: table's structure customization, when applicable
        :param do_output_xcom_push: flag indicating if the job result should be pushed into xcom.
        :type execution_date: str
        :rtype: list[BaseOperator]
        """
        return self._build_task_group(
            LayerEnum.METRIC,
            source_database_base_name,
            target_database_base_name,
            table_name,
            partitions,
            is_incremental,
            spark_session_configs,
            extra_query_template_params,
            schema,
            execution_date=execution_date,
            has_hive_sync=has_hive_sync,
            table_customization=table_customization,
            do_output_xcom_push=do_output_xcom_push,
        )
