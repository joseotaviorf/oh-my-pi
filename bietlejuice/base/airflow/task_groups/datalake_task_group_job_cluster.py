import json
from datetime import timedelta
from typing import Dict

import airflow.utils.helpers as airflow_helpers
from airflow.operators.dummy_operator import DummyOperator
from airflow.operators.databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
)
from airflow.utils.helpers import chain
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.base_task_group import BaseTaskGroup
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.formatters import StringFormatter
from bietlejuice.services import ConfigurationService
from bietlejuice.services.dag_metadata_service import DAGMetadataService

logger = QuintoAndarLogger("DatalakeTaskGroup")

AIRFLOW_DEFAULT_POOL = "default_pool"  # TODO: Add to parameter service to be created


class DatalakeTaskGroupJobCluster(BaseTaskGroup):
    """
    Responsible for creating task groups related to datalake operations
    """

    ALL_TABLES = "--all-tables"
    SINGLE_TABLE = "--table-name"

    def __init__(
        self,
        dag,
        env,
        datalake_bucket,
        relative_query_path,
        spark_jobs_path,
        athena_query_result_location,
        tree_path="",
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
        :param tree_path: The rest of the path, used for full or incremental ingestions or specific contextual ingestions e:g crawlers listings
        :type schema: str
        :param execution_timeout_hours: timeout in hours to be set to the tasks
        :type execution_timeout_hours: int
        """
        super().__init__(
            dag, env, relative_query_path, spark_jobs_path, execution_timeout_hours
        )
        self.datalake_bucket = datalake_bucket
        self.athena_query_result_location = athena_query_result_location

    def _build_raw_task_group(
        self,
        source,
        target_database_base_name,
        extraction_spark_job_file,
        execution_date="{{ ds }}",
        table_name=None,
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
        :param target_database_base_name: database base name for the target
            table database
        :type target_database_base_name: str
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

        table_name_arg = []
        tasks_name_suffix = ""
        sync_mode = self.ALL_TABLES
        layer = LayerEnum.RAW.value

        if table_name:
            sync_mode = self.SINGLE_TABLE
            table_name_arg = [table_name]
            tasks_name_suffix = StringFormatter.slugify(f"-{table_name}")

        if raw_spark_job_extra_args is None:
            raw_spark_job_extra_args = []

        load_table_task = QuintoAndarDatabricksCheckJobTaskOperator(
            databricks_conn_id="databricks_job_cluster",
            task_id=f"load-{layer}-{source}{tasks_name_suffix}",
            pool=pool,
            dag=self.dag,
            json={
                "spark_python_task": {
                    "python_file": extraction_spark_job_file,
                    "parameters": [self.env, self.datalake_bucket]
                    + raw_spark_job_extra_args,
                }
            },
            do_output_xcom_push=do_output_xcom_push,
        )

        config_service = ConfigurationService(source)

        if has_hive_sync:
            sync_metastore_tables_structure_task = QuintoAndarDatabricksCheckJobTaskOperator(
                databricks_conn_id="databricks_job_cluster",
                task_id=f"sync-hive-metastore-{layer}{tasks_name_suffix}-structure",
                dag=self.dag,
                json={
                    "spark_python_task": {
                        "python_file": self.spark_jobs_path
                        + "sync_metastore_tables_structure.py",
                        "parameters": [
                            self.datalake_bucket,
                            layer,
                            target_database_base_name,
                            sync_mode,
                        ]
                        + table_name_arg,
                    }
                },
            )

            sync_metastore_tables_partitions_task = QuintoAndarDatabricksCheckJobTaskOperator(
                databricks_conn_id="databricks_job_cluster",
                task_id=f"sync-hive-metastore-{layer}{tasks_name_suffix}-partitions",
                dag=self.dag,
                json={
                    "spark_python_task": {
                        "python_file": self.spark_jobs_path
                        + "sync_metastore_tables_partitions.py",
                        "parameters": [
                            self.datalake_bucket,
                            layer,
                            target_database_base_name,
                            sync_mode,
                        ]
                        + table_name_arg,
                    }
                },
            )

            airflow_helpers.chain(
                load_table_task,
                sync_metastore_tables_structure_task,
                sync_metastore_tables_partitions_task,
            )

            try:
                product_db_name = config_service.get_config(
                    "lineage_product_database_name"
                )
            except IndexError:
                logger.debug(
                    f"m=_build_raw_task_group, msg=could not find lineage_product_database_name in configs"
                )
                product_db_name = ""

            metadata_type = None

            if DAGMetadataService.metadata_file_exists(
                self.relative_query_path,
                layer,
                table_name,
                sync_mode == self.ALL_TABLES,
            ):
                metadata_type = MetadataTypeEnum.TAGS.value
            elif product_db_name:
                metadata_type = MetadataTypeEnum.FULL_CONTENT_LINEAGE.value

            if metadata_type:
                propagate_table_lineage_task = QuintoAndarDatabricksCheckJobTaskOperator(
                    databricks_conn_id="databricks_job_cluster",
                    dag=self.dag,
                    task_id=f"propagate-table-metadata-{layer}-{source}{tasks_name_suffix}",
                    json={
                        "spark_python_task": {
                            "python_file": f"{self.spark_jobs_path}/propagate_raw_tables_metadata.py",
                            "parameters": [
                                layer,
                                metadata_type,
                                target_database_base_name,
                                self.relative_query_path,
                                "--product-database-name",
                                product_db_name,
                                sync_mode,
                            ]
                            + table_name_arg,
                        }
                    },
                    execution_timeout=timedelta(hours=self.execution_timeout_hours),
                )

                bypass_task = DummyOperator(
                    dag=self.dag,
                    task_id=f"propagation-bypass-{layer}-{source}{tasks_name_suffix}",
                    trigger_rule="all_done",
                )

                airflow_helpers.chain(
                    sync_metastore_tables_partitions_task,
                    propagate_table_lineage_task,
                    bypass_task,
                )
                final_tasks = [sync_metastore_tables_partitions_task, bypass_task]
            else:
                logger.debug(
                    f"m=_build_raw_task_group, target_database_base_name={target_database_base_name}, "
                    f"msg=Could not infer metadata type, skipping propagate metadata task"
                )
                final_tasks = [sync_metastore_tables_partitions_task]
        else:
            final_tasks = [load_table_task]

        tb_names = []
        if (
            sync_mode == self.SINGLE_TABLE
            and DAGPackagesPathService.data_quality_tests_file_exists_in_composer(
                dag_name=self.relative_query_path,
                layer=layer,
                table_name=table_name,
                intermediate_path=tree_path,
            )
        ):
            tb_names = [table_name]
        elif sync_mode == self.ALL_TABLES:
            tb_names = DAGPackagesPathService.list_data_quality_tests_files_in_composer(
                dag_name=self.relative_query_path, layer=layer
            )

        quality_tasks = []
        for tb_name in tb_names:
            inmetro_bucket = config_service.get_config("inmetro_bucket")
            table_name_suffix = StringFormatter.slugify(f"-{tb_name}")

            data_quality_tests_task = QuintoAndarDatabricksCheckJobTaskOperator(
                databricks_conn_id="databricks_job_cluster",
                dag=self.dag,
                task_id=f"data-quality-tests-{layer}-{source}{table_name_suffix}",
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/data_quality_tests.py",
                        "parameters": [
                            self.env,
                            execution_date,
                            inmetro_bucket,
                            layer,
                            self.relative_query_path,
                            tb_name,
                            tree_path,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )

            load_table_task.set_downstream([data_quality_tests_task])
            quality_tasks.append(data_quality_tests_task)

        return DatalakeTaskGroupJobCluster.format_tasks_boundaries(
            initial_tasks=[load_table_task],
            final_tasks=final_tasks,
            independent_tasks=quality_tasks,
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
            target_database_base_name=target_database_base_name,
            extraction_spark_job_file=extraction_spark_job_file,
            raw_spark_job_extra_args=raw_spark_job_extra_args,
            pool=pool,
            has_hive_sync=has_hive_sync,
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
            target_database_base_name=target_database_base_name,
            extraction_spark_job_file=extraction_spark_job_file,
            table_name=table_name,
            raw_spark_job_extra_args=raw_spark_job_extra_args,
            pool=pool,
            has_hive_sync=has_hive_sync,
            tree_path=tree_path,
            do_output_xcom_push=do_output_xcom_push,
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
        partitions = partitions or []
        spark_session_configs = spark_session_configs or {}
        extra_query_template_params = extra_query_template_params or {}

        table_extraction_type = "incremental" if is_incremental else "full"

        load_table_task = QuintoAndarDatabricksCheckJobTaskOperator(
            databricks_conn_id="databricks_job_cluster",
            task_id=StringFormatter.slugify(f"load-{layer.value}-{table_name}"),
            dag=self.dag,
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/load_table_{table_extraction_type}.py",
                    "parameters": [
                        self.env,
                        self.datalake_bucket,
                        layer.value,
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
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
            do_output_xcom_push=do_output_xcom_push,
        )

        if has_hive_sync:
            sync_metastore_table_structure_task = QuintoAndarDatabricksCheckJobTaskOperator(
                databricks_conn_id="databricks_job_cluster",
                dag=self.dag,
                task_id=StringFormatter.slugify(
                    f"sync-hive-metastore-{layer.value}-{table_name}-structure"
                ),
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/sync_metastore_tables_structure.py",
                        "parameters": [
                            self.datalake_bucket,
                            layer.value,
                            target_database_base_name,
                            "--table-name",
                            table_name,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )

            sync_metastore_table_partitions_task = QuintoAndarDatabricksCheckJobTaskOperator(
                databricks_conn_id="databricks_job_cluster",
                dag=self.dag,
                task_id=StringFormatter.slugify(
                    f"sync-hive-metastore-{layer.value}-{table_name}-partitions"
                ),
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/sync_metastore_tables_partitions.py",
                        "parameters": [
                            self.datalake_bucket,
                            layer.value,
                            target_database_base_name,
                            "--table-name",
                            table_name,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )

            chain(
                load_table_task,
                sync_metastore_table_structure_task,
                sync_metastore_table_partitions_task,
            )

            final_tasks = [sync_metastore_table_partitions_task]
        else:
            final_tasks = [load_table_task]

        if has_hive_sync:
            if DAGMetadataService.metadata_file_exists(
                self.relative_query_path, layer.value, table_name
            ):
                propagate_table_metadata_task = QuintoAndarDatabricksCheckJobTaskOperator(
                    databricks_conn_id="databricks_job_cluster",
                    dag=self.dag,
                    task_id=StringFormatter.slugify(
                        f"propagate-table-metadata-{layer.value}-{table_name}"
                    ),
                    json={
                        "spark_python_task": {
                            "python_file": f"{self.spark_jobs_path}/propagate_table_metadata.py",
                            "parameters": [
                                layer.value,
                                MetadataTypeEnum.LINEAGE.value,
                                target_database_base_name,
                                table_name,
                            ],
                        }
                    },
                    execution_timeout=timedelta(hours=self.execution_timeout_hours),
                )

                bypass_task = DummyOperator(
                    dag=self.dag,
                    task_id=StringFormatter.slugify(
                        f"propagation-bypass-{layer.value}-{table_name}"
                    ),
                    trigger_rule="all_done",
                )

                airflow_helpers.chain(
                    sync_metastore_table_partitions_task,
                    propagate_table_metadata_task,
                    bypass_task,
                )

                final_tasks = [sync_metastore_table_partitions_task, bypass_task]

        if has_create_external_table_task:
            create_external_table_task = QuintoAndarDatabricksCheckJobTaskOperator(
                databricks_conn_id="databricks_job_cluster",
                dag=self.dag,
                task_id=StringFormatter.slugify(
                    f"create-{layer.value}-{table_name}-external-table"
                ),
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/create_external_table.py",
                        "parameters": [
                            self.env,
                            self.datalake_bucket,
                            self.athena_query_result_location,
                            layer.value,
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
            layer=layer.value,
            table_name=table_name,
            intermediate_path=tree_path,
        ):
            config_service = ConfigurationService()
            inmetro_bucket = config_service.get_config("inmetro_bucket")

            data_quality_tests_task = QuintoAndarDatabricksCheckJobTaskOperator(
                databricks_conn_id="databricks_job_cluster",
                dag=self.dag,
                task_id=StringFormatter.slugify(
                    f"data-quality-tests-{layer.value}-{table_name}"
                ),
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/data_quality_tests.py",
                        "parameters": [
                            self.env,
                            execution_date,
                            inmetro_bucket,
                            layer.value,
                            self.relative_query_path,
                            table_name,
                            tree_path,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )

            load_table_task.set_downstream([data_quality_tests_task])
            quality_tasks = [data_quality_tests_task]

        return DatalakeTaskGroupJobCluster.format_tasks_boundaries(
            initial_tasks=[load_table_task],
            final_tasks=final_tasks,
            independent_tasks=quality_tasks,
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
