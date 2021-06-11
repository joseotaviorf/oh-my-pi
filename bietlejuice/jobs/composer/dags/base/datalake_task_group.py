from datetime import timedelta

from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseTaskGroup
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
import airflow.utils.helpers as airflow_helpers

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

    def build_clean_task_group(
        self,
        source_database_base_name,
        target_database_base_name,
        table_name,
        partitions=None,
        is_incremental=False,
        spark_params={},
        extra_query_template_params=None,
        schema="",
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
        :param spark_params: general parameters to be passed to the spark job
        :type spark_params: dict
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
            spark_params,
            extra_query_template_params,
            schema,
        )

    def build_enrich_task_group(
        self,
        source_database_base_name,
        target_database_base_name,
        table_name,
        partitions=None,
        is_incremental=False,
        spark_params={},
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
        :param spark_params: general parameters to be passed to the spark job
        :type spark_params: dict
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
            spark_params,
            extra_query_template_params,
            schema,
        )

    def _build_task_group(
        self,
        layer,
        source_database_base_name,
        target_database_base_name,
        table_name,
        partitions=None,
        is_incremental=False,
        spark_params={},
        extra_query_template_params=None,
        schema="",  # TODO: Remove schema param after dags are all in pattern
        # 'schema' parameter could be replaced by source or target database_base_name.
        # However, since we have out of pattern paths in our project directory we
        # cannot chose only one now, we would need a refactoring first.
    ):
        """
        Create a task group containing 3 tasks:
        1. load table to metastore database using a sql query
        2. create a external table in Athena using metastore created before
        3. sync table from spark metastore to hive metastore

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
        :param spark_params: general parameters to be passed to the spark job
        :type spark_params: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param schema: db schema where the table is at. Used in the query path
        :type schema: str
        :return: dict with initial and final tasks of the created task group
        :rtype: dict
        """
        slugged_table_name = table_name.replace("_", "-")
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
                        str(spark_params),
                        str(extra_query_template_params),
                        schema,
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
        return DatalakeTaskGroup.format_tasks_boundaries(
            initial_tasks=[load_table_task],
            final_tasks=[create_external_table_task, sync_metastore_table_task],
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
            hive_sync_table_param="--all-tables",
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
            tasks_name_suffix=f"-{table_name.replace('_', '-')}",
            hive_sync_table_param=f"--table-name {table_name}",
            raw_spark_job_extra_args=raw_spark_job_extra_args,
            pool=pool,
        )

    def _build_raw_task_group(
        self,
        source,
        target_database_base_name,
        extraction_spark_job_file,
        hive_sync_table_param,
        tasks_name_suffix="",
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
        :param hive_sync_table_param: sync_metastore_tables spark job parameter
            for syncing a specific table or all tables from specified database
        :type hive_sync_table_param: str
        :param tasks_name_suffix: suffix for appending to default task names
        :type tasks_name_suffix: str
        :param raw_spark_job_extra_args: extra arguments to be passed to the spark job,
            default spark job parameters are [env, bucket]
        :type raw_spark_job_extra_args: list[str]
        :param pool: airflow's pool name
        :type pool: str
        :return: initial and final tasks of the created task group
        :rtype: dict
        """
        layer = LayerEnum.RAW.value
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
                        hive_sync_table_param,
                    ],
                }
            },
        )

        airflow_helpers.chain(load_table_task, sync_metastore_tables_task)

        return DatalakeTaskGroup.format_tasks_boundaries(
            initial_tasks=[load_table_task], final_tasks=[sync_metastore_tables_task]
        )
