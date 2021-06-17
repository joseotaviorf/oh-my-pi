from datetime import timedelta
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseTaskGroup
from bietlejuice.jobs.composer.base.pipeline import LayerEnum

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

    def build_dw_task_group(self, table_name, spectrum_iam_role):
        """
        Creates a task group containing the tasks:
        . load_table_to_dw_final_schema_task: load table from staging metastore
           database to final schema in s3
        . load_table_to_redshift_task: load table to Redshift copying files from
           final schema database in S3
        . sync_metastore_table_task: sync the table from spark metastore
           to hive metastore

        :param table_name: table name to be created
        :type table_name: str
        :param spectrum_iam_role: aws redshift spectrum IAM role
        :type spectrum_iam_role: str
        :return: dict with initial and final tasks of the created task group
        :rtype: dict
        """
        layer = LayerEnum.DW.value
        slugged_table_name = table_name.replace("_", "-")

        load_table_to_dw_final_schema_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=f"load-{layer}-{self.dw_schema}-{slugged_table_name}",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/load_full_table_to_dw_final_schema.py",
                    "parameters": [
                        self.env,
                        self.dw_bucket,
                        self.dw_schema,
                        table_name,
                    ],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        load_table_to_redshift_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=f"load-{self.dw_schema}-{slugged_table_name}-into-redshift",
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
        self, table_name, has_ods_migration_test=False, cluster_config_params={}
    ):
        """
        Creates a task group containing the tasks:
        . load_table_to_dw_staging_schema_task: load table to dw staging layer
        . emptiness_test_task: validate if table in staging is not empty
        . test_entity_ods_migration_task: (optional) test if migrated data from ods
         matches transformations mapped
        . add_default_row_to_dim_task: (optional) if table is a dimension, add
         default row with -1 in primary key column

        :param table_name: table name to be created
        :type table_name: str
        :param has_ods_migration_test: whether to create tasks to validate migrated
            data x ods
        :type has_ods_migration_test: bool
        :param cluster_config_params: custom config parameters to be set in spark cluster
        :type cluster_config_params: dict
        :return: dict with initial and final tasks of the created task group
        :rtype: dict
        """
        layer = LayerEnum.DW_STAGING.value
        slugged_table_name = table_name.replace("_", "-")

        load_table_to_dw_staging_schema_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=f"load-{layer}-{self.dw_schema}-{slugged_table_name}",
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/load_full_table_to_dw_staging_schema.py",
                    "parameters": [
                        self.env,
                        self.dw_bucket,
                        self.dw_schema,
                        self.relative_query_path,
                        table_name,
                        str(cluster_config_params),
                    ],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        emptiness_test_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=f"test-{layer}-{self.dw_schema}-{slugged_table_name}-emptiness",
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
                task_id=f"test-{layer}-{self.dw_schema}-{slugged_table_name}-ods-migration",
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
                task_id=f"add-default-row-to-{layer}-{self.dw_schema}-{slugged_table_name}",
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
    def is_dim(table_name):
        """
        Validates whether table is a dim according to name prefix

        :param table_name: table name
        :type table_name: str
        :rtype: bool
        """
        return table_name.startswith("dim_")
