import json
from datetime import timedelta
from typing import Dict
from os import path

from airflow.utils.helpers import chain
from airflow.operators.dummy_operator import DummyOperator
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.base.airflow.base_task_group import BaseTaskGroup
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.formatters import StringFormatter
from bietlejuice.services import ConfigurationService
from bietlejuice.services.dag_metadata_service import DAGMetadataService

AIRFLOW_DEFAULT_POOL = "default_pool"  # TODO: Add to parameter service to be created


class DatalakeTaskGroup(BaseTaskGroup):
    """
    Responsible for creating task groups related to datalake operations
    """

    ALL_TABLES = "--all-tables"
    SINGLE_TABLE = "--table-name"

    LAYER_TO_PROPAGATOR_SPARK_JOB_MAPPING = {
        LayerEnum.RAW.value: "propagate_raw_tables_metadata.py",
        LayerEnum.CLEAN.value: "propagate_table_metadata.py",
        LayerEnum.ENRICH.value: "propagate_table_metadata.py",
        LayerEnum.METRIC.value: "propagate_table_metadata.py",
        LayerEnum.REVERSE.value: "propagate_table_metadata.py",
    }

    def __init__(
        self,
        dag,
        env,
        datalake_bucket,
        relative_query_path,
        spark_jobs_path,
        athena_query_result_location,
        execution_timeout_hours=BaseTaskGroup.DEFAULT_EXECUTION_TIMEOUT_HOURS,
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
        :param athena_query_result_location: athena query results location
        :type athena_query_result_location: str
        :param execution_timeout_hours: timeout in hours to be set to the tasks
        :type execution_timeout_hours: int
        """
        super().__init__(
            dag, env, relative_query_path, spark_jobs_path, execution_timeout_hours
        )
        self.datalake_bucket = datalake_bucket
        self.athena_query_result_location = athena_query_result_location

        config_service = ConfigurationService()
        self.inmetro_bucket = config_service.get_config("inmetro_bucket")

    def _build_load_task(
        self,
        task_id_suffix: str,
        extraction_spark_job_file: str,
        do_output_xcom_push: bool,
        pool: str = AIRFLOW_DEFAULT_POOL,
        spark_job_extra_args: list = [],
    ) -> QuintoAndarDatabricksSubmitRunOperator:

        load_table_task = QuintoAndarDatabricksSubmitRunOperator(
            task_id=f"load-{task_id_suffix}",
            pool=pool,
            dag=self.dag,
            json={
                "spark_python_task": {
                    "python_file": extraction_spark_job_file,
                    "parameters": [self.env, self.datalake_bucket]
                    + spark_job_extra_args,
                }
            },
            do_output_xcom_push=do_output_xcom_push,
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        return load_table_task

    def _build_hive_sync_tasks(
        self,
        task_id_suffix: str,
        sync_mode: str,
        layer: str,
        database_name: str,
        table_name: str,
    ) -> list:

        sync_metastore_structure_task = QuintoAndarDatabricksSubmitRunOperator(
            task_id=f"sync-hive-metastore-{task_id_suffix}-structure",
            dag=self.dag,
            json={
                "spark_python_task": {
                    "python_file": path.join(
                        self.spark_jobs_path, "sync_metastore_tables_structure.py"
                    ),
                    "parameters": [
                        self.datalake_bucket,
                        layer,
                        database_name,
                        sync_mode,
                    ]
                    + ([table_name] if table_name else []),
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        sync_metastore_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
            task_id=f"sync-hive-metastore-{task_id_suffix}-partitions",
            dag=self.dag,
            json={
                "spark_python_task": {
                    "python_file": path.join(
                        self.spark_jobs_path, "sync_metastore_tables_partitions.py"
                    ),
                    "parameters": [
                        self.datalake_bucket,
                        layer,
                        database_name,
                        sync_mode,
                    ]
                    + ([table_name] if table_name else []),
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        return [sync_metastore_structure_task, sync_metastore_partitions_task]

    # TODO: This method requires a refactor ASAP due to the quantity of conditions
    def _build_metadata_propagator_tasks(
        self,
        task_id_suffix: str,
        layer: str,
        database_name: str,
        table_name: str,
        sync_mode: str = None,
        source: str = None,
        metadata_type: str = None,
    ) -> list:

        config_service = ConfigurationService(source)

        metadata_propagator_tasks = []

        try:
            product_db_name = config_service.get_config("lineage_product_database_name")
        except IndexError:
            # TODO: DIN-336 Review this try/except block after this deployment
            product_db_name = ""

        if not metadata_type:
            if DAGMetadataService.metadata_file_exists(
                relative_file_path=self.relative_query_path,
                layer=layer,
                table_name=table_name,
                check_all_tables=sync_mode == self.ALL_TABLES,
            ):
                metadata_type = MetadataTypeEnum.TAGS.value
            elif product_db_name:
                metadata_type = MetadataTypeEnum.FULL_CONTENT_LINEAGE.value

        if metadata_type:
            raw_params = (
                [
                    self.relative_query_path,
                    "--product-database-name",
                    product_db_name,
                    sync_mode,
                ]
                if layer == LayerEnum.RAW.value
                else []
            )
            propagate_table_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=f"propagate-table-metadata-{task_id_suffix}",
                json={
                    "spark_python_task": {
                        "python_file": path.join(
                            self.spark_jobs_path,
                            self.LAYER_TO_PROPAGATOR_SPARK_JOB_MAPPING[layer],
                        ),
                        "parameters": [layer, metadata_type, database_name]
                        + raw_params
                        + ([table_name] if table_name else []),
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )

            bypass_task = DummyOperator(
                dag=self.dag,
                task_id=f"propagation-bypass-{task_id_suffix}",
                trigger_rule="all_done",
            )

            metadata_propagator_tasks.extend(
                [propagate_table_metadata_task, bypass_task]
            )

        return metadata_propagator_tasks

    def _build_data_quality_tasks(
        self,
        layer: str,
        sync_mode: str,
        table_name: str,
        source: str = None,
        tree_path: str = "",
        execution_date="{{ ds }}",
    ) -> list:

        data_quality_tasks = []

        if (
            sync_mode == self.SINGLE_TABLE
            and DAGPackagesPathService.artifact_file_exists(
                artifact_type="data_quality",
                dag_name=self.relative_query_path,
                layer=layer,
                table_name=path.join(tree_path, table_name),
            )
        ):
            tables_names = [table_name]

        elif sync_mode == self.ALL_TABLES:
            tables_names = DAGPackagesPathService.list_data_quality_tests_files_in_composer(
                dag_name=self.relative_query_path, layer=layer
            )
        else:
            return data_quality_tasks

        for table in tables_names:
            task_id_suffix = StringFormatter.slugify(
                "-".join(id_part for id_part in [layer, source, table] if id_part)
            )

            data_quality_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=f"data-quality-tests-{task_id_suffix}",
                json={
                    "spark_python_task": {
                        "python_file": path.join(
                            self.spark_jobs_path, "data_quality_tests.py"
                        ),
                        "parameters": [
                            self.env,
                            execution_date,
                            self.inmetro_bucket,
                            layer,
                            self.relative_query_path,
                            table,
                            tree_path,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )

            data_quality_tasks.append(data_quality_task)

        return data_quality_tasks

    def _build_raw_task_group(
        self,
        source,
        database_name,
        extraction_spark_job_file,
        execution_date="{{ ds }}",
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
        :param execution_date: job execution date. Defaults to the airflow run date {{ ds }}
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

        layer = LayerEnum.RAW.value
        tasks_id_suffix = StringFormatter.slugify(
            "-".join(id_part for id_part in [layer, source, table_name] if id_part)
        )
        sync_mode = self.SINGLE_TABLE if table_name else self.ALL_TABLES

        load_table_task = self._build_load_task(
            pool=pool,
            task_id_suffix=tasks_id_suffix,
            extraction_spark_job_file=extraction_spark_job_file,
            spark_job_extra_args=raw_spark_job_extra_args or [],
            do_output_xcom_push=do_output_xcom_push,
        )

        if has_hive_sync:
            hive_sync_tasks = self._build_hive_sync_tasks(
                task_id_suffix=tasks_id_suffix,
                sync_mode=sync_mode,
                layer=layer,
                database_name=database_name,
                table_name=table_name,
            )

            propagate_table_metadata_tasks = self._build_metadata_propagator_tasks(
                task_id_suffix=tasks_id_suffix,
                layer=layer,
                database_name=database_name,
                table_name=table_name,
                sync_mode=sync_mode,
                source=source,
            )

            chain(load_table_task, *hive_sync_tasks, *propagate_table_metadata_tasks)
            final_tasks = [hive_sync_tasks[1]] + (
                [propagate_table_metadata_tasks[1]]
                if propagate_table_metadata_tasks
                else []
            )
        else:
            final_tasks = [load_table_task]

        quality_tasks = self._build_data_quality_tasks(
            layer=layer,
            sync_mode=sync_mode,
            table_name=table_name,
            source=source,
            tree_path=tree_path,
            execution_date=execution_date,
        )

        load_table_task.set_downstream(quality_tasks)

        return DatalakeTaskGroup.format_tasks_boundaries(
            initial_tasks=[load_table_task],
            final_tasks=final_tasks,
            independent_tasks=quality_tasks,
        )

    def _build_task_group(
        self,
        layer,
        source_database_base_name,
        target_database_base_name,
        table_name,
        partitions=None,
        is_incremental=False,
        has_create_external_table_task=True,
        spark_session_configs=None,
        extra_query_template_params=None,
        schema="",  # TODO: Remove schema param after dags are all in pattern
        # 'schema' parameter could be replaced by source or target database_base_name.
        # However, since we have out of pattern paths in our project directory we
        # cannot chose only one now, we would need a refactoring first.
        tree_path="",
        execution_date="{{ ds }}",
        has_hive_sync=True,
        table_customization=None,
        do_output_xcom_push=False,
    ):
        """
        Create a task group containing 4 tasks:
        1. load table to metastore database using a sql query
        2. create a external table in Athena using metastore created before
        3. sync table from spark metastore to hive metastore
        4. propagate the table metadata to metadata-propagator service
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
        :param has_create_external_table_task: if this table is going to be loaded into Athena
        :type has_create_external_table_task: bool
        :param spark_session_configs: custom config parameters to be set in spark session
        :type spark_session_configs: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :param execution_date: job execution date. Defaults to the airflow run date {{ ds }}
        :type execution_date: str
        :param has_hive_sync: if this table is going to have Hive sync
        :param table_customization: table's structure customization, when applicable
        :param do_output_xcom_push: flag indicating if the job result should be pushed into xcom.
        :return: dict with initial and final tasks of the created task group
        :rtype: dict
        """

        layer = layer.value
        partitions = partitions or []
        spark_session_configs = spark_session_configs or {}
        extra_query_template_params = extra_query_template_params or {}
        table_extraction_type = "incremental" if is_incremental else "full"
        tasks_id_suffix = StringFormatter.slugify(
            "-".join(id_part for id_part in [layer, table_name] if id_part)
        )

        load_table_task = self._build_load_task(
            task_id_suffix=tasks_id_suffix,
            extraction_spark_job_file=path.join(
                self.spark_jobs_path, f"load_table_{table_extraction_type}.py"
            ),
            do_output_xcom_push=do_output_xcom_push,
            spark_job_extra_args=[
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
            ],
        )

        if has_hive_sync:
            hive_sync_tasks = self._build_hive_sync_tasks(
                task_id_suffix=tasks_id_suffix,
                sync_mode=self.SINGLE_TABLE,
                layer=layer,
                database_name=target_database_base_name,
                table_name=table_name,
            )

            propagate_table_metadata_tasks = self._build_metadata_propagator_tasks(
                task_id_suffix=tasks_id_suffix,
                layer=layer,
                database_name=target_database_base_name,
                table_name=table_name,
                metadata_type=MetadataTypeEnum.LINEAGE.value,
            )

            chain(load_table_task, *hive_sync_tasks, *propagate_table_metadata_tasks)
            final_tasks = [hive_sync_tasks[1]] + (
                [propagate_table_metadata_tasks[1]]
                if propagate_table_metadata_tasks
                else []
            )
        else:
            final_tasks = [load_table_task]

        if has_create_external_table_task:
            create_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=f"create-{tasks_id_suffix}-external-table",
                json={
                    "spark_python_task": {
                        "python_file": path.join(
                            self.spark_jobs_path, "create_external_table.py"
                        ),
                        "parameters": [
                            self.env,
                            self.datalake_bucket,
                            self.athena_query_result_location,
                            layer,
                            target_database_base_name,
                            table_name,
                            str(partitions),
                            is_incremental,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )

            load_table_task.set_downstream(create_external_table_task)

            final_tasks = [create_external_table_task] + final_tasks

        quality_tasks = []
        if DAGPackagesPathService.data_quality_tests_file_exists_in_composer(
            dag_name=self.relative_query_path,
            layer=layer,
            table_name=table_name,
            intermediate_path=tree_path,
        ):
            quality_tasks = self._build_data_quality_tasks(
                layer=layer,
                sync_mode=self.SINGLE_TABLE,
                table_name=table_name,
                tree_path=tree_path,
                execution_date=execution_date,
            )

            load_table_task.set_downstream(quality_tasks)

        return DatalakeTaskGroup.format_tasks_boundaries(
            initial_tasks=[load_table_task],
            final_tasks=final_tasks,
            independent_tasks=quality_tasks,
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
        has_create_external_table_task=True,
        spark_session_configs=None,
        extra_query_template_params=None,
        schema="",
        tree_path="",
        execution_date="{{ ds }}",
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
        :param has_create_external_table_task: if this table is going to be loaded into Athena
        :type has_create_external_table_task: bool
        :param spark_session_configs: custom config parameters to be set in spark session
        :type spark_session_configs: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :param execution_date: job execution date. Defaults to the airflow run date {{ ds }}
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
            has_create_external_table_task,
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
        has_create_external_table_task=True,
        spark_session_configs=None,
        extra_query_template_params=None,
        schema="",
        execution_date="{{ ds }}",
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
        :param has_create_external_table_task: if this table is going to be loaded into Athena
        :type has_create_external_table_task: bool
        :param spark_session_configs: custom config parameters to be set in spark session
        :type spark_session_configs: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :param execution_date: job execution date. Defaults to the airflow run date {{ ds }}
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
            has_create_external_table_task,
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
        execution_date="{{ ds }}",
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
        :param has_create_external_table_task: if this table is going to be loaded into Athena
        :type has_create_external_table_task: bool
        :param spark_session_configs: custom config parameters to be set in spark session
        :type spark_session_configs: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :param execution_date: job execution date. Defaults to the airflow run date {{ ds }}
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
            has_create_external_table_task,
            spark_session_configs,
            extra_query_template_params,
            schema,
            execution_date=execution_date,
            has_hive_sync=has_hive_sync,
            table_customization=table_customization,
            do_output_xcom_push=do_output_xcom_push,
        )
