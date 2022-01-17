import json
from datetime import timedelta

import airflow.utils.helpers as airflow_helpers
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
)
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("DatalakeTaskGroup")

from bietlejuice.jobs.composer.base.airflow import BaseTaskGroup
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.jobs.composer.formatters import StringFormatter
from bietlejuice.jobs.composer.services import FileService, ConfigurationService

AIRFLOW_DEFAULT_POOL = "default_pool"  # TODO: Add to parameter service to be created


class DatalakeTaskGroup(BaseTaskGroup):
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
        tree_path = "",
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
        table_name=None,
        raw_spark_job_extra_args=None,
        pool=AIRFLOW_DEFAULT_POOL,
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
        :param table_name: the table name when loading a single table
        :type table_name: str
        :param raw_spark_job_extra_args: extra arguments to be passed to the spark job,
            default spark job parameters are [env, bucket]
        :type raw_spark_job_extra_args: list[str]
        :param pool: airflow's pool name
        :type pool: str
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

        load_table_task = QuintoAndarDatabricksSubmitRunOperator(
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
        )

        sync_metastore_tables_task = QuintoAndarDatabricksSubmitRunOperator(
            task_id=f"sync-hive-metastore-{layer}{tasks_name_suffix}",
            dag=self.dag,
            json={
                "spark_python_task": {
                    "python_file": self.spark_jobs_path + "sync_metastore_tables.py",
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

        airflow_helpers.chain(load_table_task, sync_metastore_tables_task)

        metadata_type = None
        try:
            config_service = ConfigurationService(source)
            product_db_name = config_service.get_config("lineage_product_database_name")
        except IndexError:
            logger.debug(
                f"m=_build_raw_task_group, msg=could not find lineage_product_database_name in configs"
            )
            product_db_name = ""

        if FileService.metadata_file_exists(
            self.relative_query_path, layer, table_name, sync_mode == self.ALL_TABLES
        ):
            metadata_type = MetadataTypeEnum.TAGS.value
        elif product_db_name:
            metadata_type = MetadataTypeEnum.FULL_CONTENT_LINEAGE.value

        if metadata_type:
            propagate_table_lineage_task = QuintoAndarDatabricksSubmitRunOperator(
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
            sync_metastore_tables_task.set_downstream([propagate_table_lineage_task])
            final_tasks = [propagate_table_lineage_task]
        else:
            logger.debug(
                f"m=_build_raw_task_group, target_database_base_name={target_database_base_name}, "
                f"msg=Could not infer metadata type, skipping propagate metadata task"
            )
            final_tasks = [sync_metastore_tables_task]

        if (
            sync_mode == self.SINGLE_TABLE
            and FileService.data_quality_tests_file_exists(
                self.relative_query_path, layer, table_name
            )
        ):
            tb_names = [table_name]
        else:
            tb_names = FileService.list_data_quality_tests_files(
                self.relative_query_path, layer
            )

        quality_tasks = []
        for tb_name in tb_names:
            table_name_suffix = StringFormatter.slugify(f"-{tb_name}")
            data_quality_tests_table_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=f"data-quality-tests-{layer}-{source}{table_name_suffix}",
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/data_quality_tests_table.py",
                        "parameters": [],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )
            load_table_task.set_downstream([data_quality_tests_table_task])
            quality_tasks.append(data_quality_tests_table_task)

        return DatalakeTaskGroup.format_tasks_boundaries(
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
        :return: initial and final tasks of the created task group
        :rtype: dict
        """
        return self._build_raw_task_group(
            source=source,
            target_database_base_name=target_database_base_name,
            extraction_spark_job_file=extraction_spark_job_file,
            raw_spark_job_extra_args=raw_spark_job_extra_args,
            pool=pool,
        )

    def build_raw_task_group_for_single_table(
        self,
        source,
        target_database_base_name,
        table_name,
        extraction_spark_job_file,
        raw_spark_job_extra_args=None,
        pool=AIRFLOW_DEFAULT_POOL,
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
        )

    def _build_task_group(
        self,
        layer,
        source_database_base_name,
        target_database_base_name,
        table_name,
        partitions=None,
        is_incremental=False,
        cluster_config_params={},
        extra_query_template_params=None,
        schema="",  # TODO: Remove schema param after dags are all in pattern
        # 'schema' parameter could be replaced by source or target database_base_name.
        # However, since we have out of pattern paths in our project directory we
        # cannot chose only one now, we would need a refactoring first.
        tree_path="",
    ):
        """
        Create a task group containing 4 tasks:
        1. load table to metastore database using a sql query
        2. create a external table in Athena using metastore created before
        3. sync table from spark metastore to hive metastore
        4. propagate the table metadata to metadata-propagator service

        :param layer: layer Enum
        :type layer: bietlejuice.jobs.composer.base.pipeline.LayerEnum member
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
        :param cluster_config_params: custom config parameters to be set in spark cluster
        :type cluster_config_params: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :return: dict with initial and final tasks of the created task group
        :rtype: dict
        """
        slugged_table_name = StringFormatter.slugify(table_name)
        partitions = partitions or []
        extra_query_template_params = extra_query_template_params or {}

        load_table_mode = "incremental" if is_incremental else "full"

        load_table_task = QuintoAndarDatabricksSubmitRunOperator(
            task_id=f"load-{layer.value}-{slugged_table_name}",
            dag=self.dag,
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/load_table_{load_table_mode}.py",
                    "parameters": [
                        self.env,
                        self.datalake_bucket,
                        layer.value,
                        source_database_base_name,
                        target_database_base_name,
                        self.relative_query_path,
                        table_name,
                        str(partitions),
                        "{{ ds }}",
                        json.dumps(cluster_config_params),
                        str(extra_query_template_params),
                        schema,
                        tree_path
                    ],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        create_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=f"create-{layer.value}-{slugged_table_name}-external-table",
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

        sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=f"sync-hive-metastore-{layer.value}-{slugged_table_name}",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/sync_metastore_tables.py",
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

        load_table_task.set_downstream(
            [create_external_table_task, sync_metastore_table_task]
        )

        final_tasks = [create_external_table_task, sync_metastore_table_task]

        if FileService.metadata_file_exists(
            self.relative_query_path, layer.value, table_name
        ):
            propagate_table_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=f"propagate-table-metadata-{layer.value}-{slugged_table_name}",
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
            sync_metastore_table_task.set_downstream([propagate_table_metadata_task])
            final_tasks = [create_external_table_task, propagate_table_metadata_task]

        quality_tasks = []
        if FileService.data_quality_tests_file_exists(
            self.relative_query_path, layer.value, table_name
        ):
            data_quality_tests_table_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=f"data-quality-tests-{layer.value}-{slugged_table_name}",
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/data_quality_tests_table.py",
                        "parameters": [],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )
            load_table_task.set_downstream([data_quality_tests_table_task])
            quality_tasks = [data_quality_tests_table_task]

        return DatalakeTaskGroup.format_tasks_boundaries(
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
        cluster_config_params={},
        extra_query_template_params=None,
        schema="",
        tree_path= "",
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
        :param cluster_config_params: custom config parameters to be set in spark cluster
        :type cluster_config_params: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :rtype: list[BaseOperator]
        """
        
        return self._build_task_group(
            LayerEnum.CLEAN,
            source_database_base_name,
            target_database_base_name,
            table_name,
            partitions,
            is_incremental,
            cluster_config_params,
            extra_query_template_params,
            schema,
            tree_path,
        )

    def build_enrich_task_group(
        self,
        source_database_base_name,
        target_database_base_name,
        table_name,
        partitions=None,
        is_incremental=False,
        cluster_config_params={},
        extra_query_template_params=None,
        schema="",
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
        :param cluster_config_params: custom config parameters to be set in spark cluster
        :type cluster_config_params: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :rtype: list[BaseOperator]
        """
        return self._build_task_group(
            LayerEnum.ENRICH,
            source_database_base_name,
            target_database_base_name,
            table_name,
            partitions,
            is_incremental,
            cluster_config_params,
            extra_query_template_params,
            schema,
        )
