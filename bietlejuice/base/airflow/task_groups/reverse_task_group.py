import json
from datetime import timedelta
from databricks_plugin import QuintoAndarDatabricksSubmitRunOperator
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.base_task_group import BaseTaskGroup
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services import ConfigurationService

logger = QuintoAndarLogger("ReverseTaskGroup")


class ReverseTaskGroup(BaseTaskGroup):
    """
    Responsible for creating task groups related to reverse etl operations
    """

    ALL_TABLES = "--all-tables"
    SINGLE_TABLE = "--table-name"

    def __init__(
        self,
        dag,
        env,
        s3_bucket,
        relative_query_path,
        spark_jobs_path,
        execution_timeout_hours=BaseTaskGroup.DEFAULT_EXECUTION_TIMEOUT_HOURS,
        databricks_conn_id="databricks_default",
    ):
        """
        :param dag: main dag instance
        :type dag: airflow.models.DAG
        :param env: forno or prod environments
        :type env: str
        :param s3_bucket: datalake bucket in S3
        :type s3_bucket: str
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
        self.s3_bucket = s3_bucket
        self.databricks_conn_id = databricks_conn_id

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
        tree_path="",
        execution_date="{{ data_interval_start | ds }}",
        table_customization=None,
    ):
        """
        Create a task group containing the tasks:
        1. load table to metastore database using a sql query
        2. data quality tasks if existent

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
        :param execution_date: job execution date. Defaults to the start of the data interval {{ data_interval_start | ds }}
        :type execution_date: str
        :param table_customization: table's structure customization, when applicable
        :return: dict with initial and final tasks of the created task group
        :rtype: dict
        """
        partitions = partitions or []
        spark_session_configs = spark_session_configs or {}
        extra_query_template_params = extra_query_template_params or {}

        load_table_mode = "incremental" if is_incremental else "full"

        load_table_task = QuintoAndarDatabricksSubmitRunOperator(
            task_id=ReverseTaskGroup.generate_default_task_id(
                task_prefix=ReverseTaskGroup.LOAD_TASK_PREFIX,
                layer=LayerEnum.REVERSE,
                schema=source_database_base_name,
                table_name=table_name,
            ),
            dag=self.dag,
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/load_reverse_table_{load_table_mode}.py",
                    "parameters": [
                        self.env,
                        self.s3_bucket,
                        layer.value,
                        source_database_base_name,
                        target_database_base_name,
                        self.relative_query_path,
                        table_name,
                        str(partitions),
                        execution_date,
                        json.dumps(spark_session_configs),
                        str(extra_query_template_params),
                        "",
                        tree_path,
                    ],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
            databricks_conn_id=self.databricks_conn_id,
        )

        final_tasks = [load_table_task]

        quality_tasks = []
        if DAGPackagesPathService.data_quality_tests_file_exists_in_composer(
            self.relative_query_path, layer.value, table_name
        ):
            config_service = ConfigurationService()
            inmetro_bucket = config_service.get_config("inmetro_bucket")

            data_quality_tests_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=ReverseTaskGroup.generate_default_task_id(
                    task_prefix=ReverseTaskGroup.DATA_QUALITY_TESTS_TASK_PREFIX,
                    layer=LayerEnum.REVERSE,
                    schema=source_database_base_name,
                    table_name=table_name,
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
                databricks_conn_id=self.databricks_conn_id,
            )

            load_table_task.set_downstream([data_quality_tests_task])
            quality_tasks = [data_quality_tests_task]

        return ReverseTaskGroup.format_tasks_boundaries(
            initial_tasks=[load_table_task],
            final_tasks=final_tasks,
            independent_tasks=quality_tasks,
        )

    def build_reverse_task_group(
        self,
        source_database_base_name,
        target_database_base_name,
        table_name,
        partitions=None,
        is_incremental=False,
        spark_session_configs=None,
        extra_query_template_params=None,
        execution_date="{{ data_interval_start | ds }}",
        table_customization=None,
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
        :param spark_session_configs: custom config parameters to be set in spark session
        :type spark_session_configs: dict
        :param extra_query_template_params: filter parameters applied to
            the query besides year, month and day
        :type extra_query_template_params: dict
        :param execution_date: job execution date. Defaults to the start of the data interval {{ data_interval_start | ds }}
        :param table_customization: table's structure customization, when applicable
        :type execution_date: str
        :rtype: list[BaseOperator]
        """
        return self._build_task_group(
            LayerEnum.REVERSE,
            source_database_base_name,
            target_database_base_name,
            table_name,
            partitions,
            is_incremental,
            spark_session_configs,
            extra_query_template_params,
            execution_date=execution_date,
            table_customization=table_customization,
        )
