import json
from datetime import timedelta
from typing import List, Dict

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
        has_load_to_redshift_task: bool = True,
        table_customization: Dict[str, Dict[str, str]] = None,
    ) -> dict:
        """
        Creates a task group containing the tasks:
        . load_table_to_dw_final_schema_task: load table from staging metastore
           database to final schema in s3
        . load_table_to_redshift_task: load table to Redshift copying files from
           final schema database in S3, created only if has_load_to_redshift_task is True
        . sync_metastore_table_task: sync the table from spark metastore
           to hive metastore
        . propagate_table_metadata_task: propagates to metadata-propagator service
           the metadata of the table

        :param table_name: table name to be created
        :param spectrum_iam_role: aws redshift spectrum IAM role
        :param is_incremental: if this table uses incremental load type
        :param partitions: list of columns to partition table
        :type partitions: list[str]
        :param extra_query_template_params: additional parameters to be supplied to query template
        :param has_load_to_redshift_task: If this table is going to be loaded into redshift
        :param table_customization: table's structure customization, when applicable
        :return: dict with initial and final tasks of the created task group
        :rtype: dict[str:list[airflow.models.BaseOperator]]
        """
        layer = LayerEnum.DW.value
        table_customization = table_customization or {}

        table_database_schema = self.__get_table_schema(table_customization)
        table_extraction_type = self.__get_table_extraction_type(
            table_customization, is_incremental
        )
        partitions = self.__get_table_partitions(table_customization, partitions)
        extra_query_template_params = extra_query_template_params or {}
        incremental_params = (
            ["{{ ds }}", json.dumps(extra_query_template_params)]
            if table_extraction_type == "incremental"
            else []
        )

        load_table_to_dw_final_schema_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=StringFormatter.slugify(
                f"load-{layer}-{table_database_schema}-{table_name}"
            ),
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/load_{table_extraction_type}_table_to_dw_final_schema.py",
                    "parameters": [
                        self.env,
                        self.dw_bucket,
                        table_database_schema,
                        table_name,
                        json.dumps(partitions),
                    ]
                    + incremental_params,
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        final_tasks = []

        if has_load_to_redshift_task:
            load_table_to_redshift_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=StringFormatter.slugify(
                    f"load-{table_database_schema}-{table_name}-into-redshift"
                ),
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/load_table_to_redshift.py",
                        "parameters": [
                            self.env,
                            spectrum_iam_role,
                            self.dw_bucket,
                            table_database_schema,
                            table_name,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )
            load_table_to_dw_final_schema_task.set_downstream(
                load_table_to_redshift_task
            )
            final_tasks.append(load_table_to_redshift_task)

        sync_metastore_table_structure_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=StringFormatter.slugify(
                f"sync-hive-metastore-{layer}-{table_name}-structure"
            ),
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/sync_metastore_tables_structure.py",
                    "parameters": [
                        self.dw_bucket,
                        layer,
                        table_database_schema,
                        "--table-name",
                        table_name,
                    ],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        sync_metastore_tables_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=StringFormatter.slugify(
                f"sync-hive-metastore-{layer}-{table_name}-partitions"
            ),
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/sync_metastore_tables_partitions.py",
                    "parameters": [
                        self.dw_bucket,
                        layer,
                        table_database_schema,
                        "--table-name",
                        table_name,
                    ],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        final_tasks.append(sync_metastore_tables_partitions_task)

        if DAGMetadataService.metadata_file_exists(
            self.relative_query_path, layer, table_name
        ):
            propagate_table_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=StringFormatter.slugify(
                    f"propagate-table-metadata-{layer}-{table_name}"
                ),
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/propagate_table_metadata.py",
                        "parameters": [
                            layer,
                            MetadataTypeEnum.LINEAGE.value,
                            table_database_schema,
                            table_name,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )

            dummy_task = DummyOperator(
                dag=self.dag,
                task_id=f"bridge-{layer}-{table_name}",
                trigger_rule="all_done",
            )

            chain(
                sync_metastore_tables_partitions_task,
                propagate_table_metadata_task,
                dummy_task,
            )
            final_tasks.append(dummy_task)

        chain(
            load_table_to_dw_final_schema_task,
            sync_metastore_table_structure_task,
            sync_metastore_tables_partitions_task,
        )

        return DWTaskGroup.format_tasks_boundaries(
            initial_tasks=[load_table_to_dw_final_schema_task], final_tasks=final_tasks
        )

    def build_dw_staging_task_group(
        self,
        table_name: str,
        execution_date="{{ ds }}",
        is_incremental: bool = False,
        partitions: List[str] = None,
        extra_query_template_params: dict = None,
        cluster_config_params: dict = None,
        tree_path: str = "",
        table_customization: Dict[str, Dict[str, str]] = None,
    ) -> dict:
        """
        Creates a task group containing the default loading task:
        . load_table_to_dw_staging_schema_task: load table to dw staging layer
        For full load pipelines, it builds additional task groups

        :param table_name: table name to be created
        :param execution_date: execution date got from Airflow's DAG Run, via Jinja template
        :param is_incremental: if this table uses incremental load type
        :param partitions: list of columns to partition table
        :param extra_query_template_params: additional parameters to be supplied to query template
        :param cluster_config_params: custom config parameters to be set in spark cluster
        :param tree_path: subfolder where the query is located. By default, an empty string, which means it's in the root folder "dw"
        :param table_customization: table's structure customization, when applicable
        :return: dict with initial and final tasks of the created task group
        :rtype: dict[str:list[airflow.models.BaseOperator]]
        """
        layer = LayerEnum.DW_STAGING.value
        table_customization = table_customization or {}

        table_database_schema = self.__get_table_schema(table_customization)
        table_extraction_type = self.__get_table_extraction_type(
            table_customization, is_incremental
        )
        partitions = self.__get_table_partitions(table_customization, partitions)
        is_incremental = table_extraction_type == "incremental"
        extra_query_template_params = extra_query_template_params or {}
        cluster_config_params = cluster_config_params or {}

        load_table_to_dw_staging_params = [
            self.env,
            self.dw_bucket,
            table_database_schema,
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
            task_id=StringFormatter.slugify(
                f"load-{layer}-{table_database_schema}-{table_name}"
            ),
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/load_{table_extraction_type}_table_to_dw_staging_schema.py",
                    "parameters": load_table_to_dw_staging_params
                    + [json.dumps(cluster_config_params), tree_path],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        quality_tasks = []
        if DAGPackagesPathService.data_quality_tests_file_exists_in_composer(
            self.relative_query_path, layer, table_name
        ):
            config_service = ConfigurationService()
            inmetro_bucket = config_service.get_config("inmetro_bucket")

            data_quality_tests_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=StringFormatter.slugify(
                    f"data-quality-tests-{layer}-{table_database_schema}-{table_name}"
                ),
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/data_quality_tests.py",
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
            load_table_to_dw_staging_schema_task.set_downstream(
                [data_quality_tests_task]
            )
            quality_tasks = [data_quality_tests_task]

        if table_extraction_type == "incremental":
            return DWTaskGroup.format_tasks_boundaries(
                initial_tasks=[load_table_to_dw_staging_schema_task],
                final_tasks=[load_table_to_dw_staging_schema_task],
                independent_tasks=quality_tasks,
            )
        else:
            return self._build_dw_staging_full_load_extra_tasks(
                load_table_to_dw_staging_schema_task=load_table_to_dw_staging_schema_task,
                table_name=table_name,
                table_database_schema=table_database_schema,
                independent_tasks=quality_tasks,
            )

    def _build_dw_staging_full_load_extra_tasks(
        self,
        load_table_to_dw_staging_schema_task,
        table_name: str,
        table_database_schema,
        independent_tasks: list = [],
    ) -> dict:
        """
        For full load pipelines, it builds the additional tasks:
        . emptiness_test_task: validate if table in staging is not empty
        . add_default_row_to_dim_task: (optional) if table is a dimension, add
         default row with -1 in primary key column

        :param table_name: table name to be created
        :param table_database_schema: table's database schema
        :return: dict with initial and final tasks of the created task group
        :rtype: dict[str:list[airflow.models.BaseOperator]]
        """
        layer = LayerEnum.DW_STAGING.value

        # TODO: Remove this test once we decide that our Data Quality validations will block downstream tasks
        emptiness_test_task = QuintoAndarDatabricksSubmitRunOperator(
            dag=self.dag,
            task_id=StringFormatter.slugify(
                f"test-{layer}-{table_database_schema}-{table_name}-emptiness"
            ),
            json={
                "spark_python_task": {
                    "python_file": f"{self.spark_jobs_path}/emptiness_test.py",
                    "parameters": [table_database_schema, table_name],
                }
            },
            execution_timeout=timedelta(hours=self.execution_timeout_hours),
        )

        test_tasks = [emptiness_test_task]

        if self.is_dim(table_name):
            add_default_row_to_dim_task = QuintoAndarDatabricksSubmitRunOperator(
                dag=self.dag,
                task_id=StringFormatter.slugify(
                    f"add-default-row-to-{layer}-{table_database_schema}-{table_name}"
                ),
                json={
                    "spark_python_task": {
                        "python_file": f"{self.spark_jobs_path}/add_default_row_to_dim.py",
                        "parameters": [
                            self.env,
                            self.dw_bucket,
                            table_database_schema,
                            layer,
                            table_name,
                        ],
                    }
                },
                execution_timeout=timedelta(hours=self.execution_timeout_hours),
            )
            chain(
                load_table_to_dw_staging_schema_task,
                add_default_row_to_dim_task,
                test_tasks,
            )
        else:
            chain(load_table_to_dw_staging_schema_task, test_tasks)

        return DWTaskGroup.format_tasks_boundaries(
            initial_tasks=[load_table_to_dw_staging_schema_task],
            final_tasks=test_tasks,
            independent_tasks=independent_tasks,
        )

    def __get_table_schema(self, table_customization):
        table_schema = table_customization.get("custom_schema", self.dw_schema)
        return table_schema

    def __get_table_partitions(self, table_customization, partitions):
        table_partitions = table_customization.get("partitions", partitions)
        return table_partitions

    def __get_table_extraction_type(self, table_customization, is_incremental):
        table_extraction_type = table_customization.get(
            "extraction_type", "incremental" if is_incremental else "full"
        )
        return table_extraction_type

    @staticmethod
    def is_dim(table_name: str) -> bool:
        """
        Validates whether table is a dim according to name prefix

        :param table_name: table name
        """
        return table_name.startswith("dim_")
