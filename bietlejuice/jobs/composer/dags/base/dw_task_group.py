from datetime import timedelta
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
)
import json
from bietlejuice.jobs.composer.base.airflow import BaseTaskGroup
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.formatters import StringFormatter

import airflow.utils.helpers as airflow_helpers
from airflow.models import Variable


class DWTaskGroup(BaseTaskGroup):
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
        """
        :param dag: main dag instance
        :type dag: airflow.models.DAG
        :param env: forno or prod environments
        :type env: str
        :param dw_bucket: dw bucket in S3
        :type dw_bucket: str
        :param dw_schema: dw schema name
        :type dw_schema: str
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
        self.dw_bucket = dw_bucket
        self.dw_schema = dw_schema

    def build_dw_task_group(
        self,
        table_name: str,
        spectrum_iam_role: str,
        is_incremental: bool = False,
        partitions: list = None,
        extra_query_template_params: dict = None,
    ) -> dict:
        """
        Creates a task group containing the tasks:
        . load_table_to_dw_final_schema_task: load table from staging metastore
           database to final schema in s3
        . load_table_to_redshift_task: load table to Redshift copying files from
           final schema database in S3
        . sync_metastore_table_task: sync the table from spark metastore
           to hive metastore

        :param table_name: table name to be created
        :param spectrum_iam_role: aws redshift spectrum IAM role
        :param is_incremental: if this table uses incremental load type
        :param partitions: list of columns to partition table
        :type partitions: list[str]
        :param extra_query_template_params: additional parameters to be supplied to query template
        :return: dict with initial and final tasks of the created task group
        :rtype: dict[str:list[airflow.models.BaseOperator]]
        """
        layer = LayerEnum.DW.value
        slugged_dw_schema = StringFormatter.slugify(self.dw_schema)
        slugged_table_name = StringFormatter.slugify(table_name)
        extra_query_template_params = extra_query_template_params or {}

        table_load_mode = self._get_load_mode(is_incremental)

        load_table_to_dw_final_schema_params = [
            self.env,
            self.dw_bucket,
            self.dw_schema,
            table_name,
        ]
        if is_incremental:
            load_table_to_dw_final_schema_params += [
                str(partitions),
                "{{ ds }}",
                json.dumps(extra_query_template_params),
            ]

        load_table_to_dw_final_schema_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=f"load-{layer}-{slugged_dw_schema}-{slugged_table_name}",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/load_{table_load_mode}_table_to_dw_final_schema.py",
                    "parameters": load_table_to_dw_final_schema_params,
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        load_table_to_redshift_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=f"load-{slugged_dw_schema}-{slugged_table_name}-into-redshift",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/load_table_to_redshift.py",
                    "parameters": [
                        self.env,
                        spectrum_iam_role,
                        self.dw_bucket,
                        self.dw_schema,
                        table_name,
                    ],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=f"sync-hive-metastore-{layer}-{slugged_table_name}",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/sync_metastore_tables.py",
                    "parameters": [
                        self.dw_bucket,
                        layer,
                        self.dw_schema,
                        "--table-name",
                        table_name,
                    ],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        load_table_to_dw_final_schema_task.set_downstream(
            [sync_metastore_table_task, load_table_to_redshift_task]
        )

        return DWTaskGroup.format_tasks_boundaries(
            initial_tasks=[load_table_to_dw_final_schema_task],
            final_tasks=[load_table_to_redshift_task, sync_metastore_table_task],
        )

    def build_dw_staging_task_group(
        self,
        table_name: str,
        is_incremental: bool = False,
        partitions: list = None,
        has_ods_migration_test: bool = False,
        extra_query_template_params: dict = None,
        cluster_config_params: dict = None,
    ) -> dict:
        """
        Creates a task group containing the default loading task:
        . load_table_to_dw_staging_schema_task: load table to dw staging layer
        For full load pipelines, it builds additional task groups

        :param table_name: table name to be created
        :param is_incremental: if this table uses incremental load type
        :param partitions: list of columns to partition table
        :type partitions: list[str]
        :param has_ods_migration_test: whether to create tasks to validate migrated
            data x ods
        :param extra_query_template_params: additional parameters to be supplied to query template
        :param cluster_config_params: custom config parameters to be set in spark cluster
        :return: dict with initial and final tasks of the created task group
        :rtype: dict[str:list[airflow.models.BaseOperator]]
        """
        layer = LayerEnum.DW_STAGING.value
        partitions = partitions or []
        extra_query_template_params = extra_query_template_params or {}
        cluster_config_params = cluster_config_params or {}

        slugged_layer = StringFormatter.slugify(layer)
        slugged_dw_schema = StringFormatter.slugify(self.dw_schema)
        slugged_table_name = StringFormatter.slugify(table_name)
        table_load_mode = self._get_load_mode(is_incremental)

        load_table_to_dw_staging_params = [
            self.env,
            self.dw_bucket,
            self.dw_schema,
            self.relative_query_path,
            table_name,
        ]

        if is_incremental:
            load_table_to_dw_staging_params += [
                str(partitions),
                "{{ ds }}",
                json.dumps(extra_query_template_params),
            ]

        load_table_to_dw_staging_schema_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=f"load-{slugged_layer}-{slugged_dw_schema}-{slugged_table_name}",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/load_{table_load_mode}_table_to_dw_staging_schema.py",
                    "parameters": load_table_to_dw_staging_params
                    + [str(cluster_config_params)],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        if is_incremental:
            return DWTaskGroup.format_tasks_boundaries(
                initial_tasks=[load_table_to_dw_staging_schema_task],
                final_tasks=[load_table_to_dw_staging_schema_task],
            )
        else:
            return self._build_dw_staging_full_load_extra_tasks(
                load_table_to_dw_staging_schema_task=load_table_to_dw_staging_schema_task,
                table_name=table_name,
                has_ods_migration_test=has_ods_migration_test,
            )

    def _build_dw_staging_full_load_extra_tasks(
        self,
        load_table_to_dw_staging_schema_task,
        table_name: str,
        has_ods_migration_test: bool = False,
    ) -> dict:
        """
        For full load pipelines, it builds the additional tasks:
        . emptiness_test_task: validate if table in staging is not empty
        . test_entity_ods_migration_task: (optional) test if migrated data from ods
         matches transformations mapped
        . add_default_row_to_dim_task: (optional) if table is a dimension, add
         default row with -1 in primary key column

        :param table_name: table name to be created
        :param has_ods_migration_test: whether to create tasks to validate migrated
            data versus ods
        :return: dict with initial and final tasks of the created task group
        :rtype: dict[str:list[airflow.models.BaseOperator]]
        """
        layer = LayerEnum.DW_STAGING.value
        slugged_layer = StringFormatter.slugify(layer)
        slugged_dw_schema = StringFormatter.slugify(self.dw_schema)
        slugged_table_name = StringFormatter.slugify(table_name)

        emptiness_test_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=f"test-{slugged_layer}-{slugged_dw_schema}-{slugged_table_name}-emptiness",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/emptiness_test.py",
                    "parameters": [self.dw_schema, table_name],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        test_tasks = [emptiness_test_task]
        if has_ods_migration_test:
            test_entity_ods_migration_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=f"test-{slugged_layer}-{slugged_dw_schema}-{slugged_table_name}-ods-migration",
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/test_ods_migration.py",
                        "parameters": [
                            self.env,
                            table_name,
                            Variable.get("ODS_MIGRATION_TESTS_THRESHOLD"),
                            "{{ ds }}",
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )
            test_tasks.append(test_entity_ods_migration_task)

        if self.is_dim(table_name):
            add_default_row_to_dim_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=f"add-default-row-to-{slugged_layer}-{slugged_dw_schema}-{slugged_table_name}",
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/add_default_row_to_dim.py",
                        "parameters": [
                            self.env,
                            self.dw_bucket,
                            self.dw_schema,
                            layer,
                            table_name,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )
            airflow_helpers.chain(
                load_table_to_dw_staging_schema_task,
                add_default_row_to_dim_task,
                test_tasks,
            )
        else:
            airflow_helpers.chain(load_table_to_dw_staging_schema_task, test_tasks)

        return DWTaskGroup.format_tasks_boundaries(
            initial_tasks=[load_table_to_dw_staging_schema_task], final_tasks=test_tasks
        )

    @staticmethod
    def is_dim(table_name: str) -> bool:
        """
        Validates whether table is a dim according to name prefix

        :param table_name: table name
        """
        return table_name.startswith("dim_")
