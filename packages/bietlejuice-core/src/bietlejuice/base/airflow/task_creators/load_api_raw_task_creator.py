"""
Task creator for API Ingestion raw layer.

Creates tasks that execute the reusable load_api_ingestion_raw Spark job,
which fetches data from REST APIs using declarative YAML configuration.
"""

import json

from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator

from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.airflow.task_creators.load_task_creator import LoadTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes


class LoadAPIRawTaskCreator(LoadTaskCreator):
    """
    Creates the task that loads raw data from REST APIs via the reusable
    load_api_ingestion_raw Spark job.
    """

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_api_ingestion_raw"

    def __init__(self, dag_execution_context, produce_datasets=True):
        super().__init__(
            dag_execution_context,
            produce_datasets,
            storage_format=StorageFormatEnum.JSON,
        )

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        """
        Builds the argument list for the load_api_ingestion_raw Spark job.

        Must stay in sync with ``dags/cross/base/spark_jobs/load_api_ingestion_raw.py``
        positional arguments (no ``--table-privileges`` on that job).

        ``load_start_date`` / ``load_end_date`` follow the same extra-params
        resolution as query/CDC task creators so a table can shift its window
        without changing Spark or the rest of the DAG.
        """
        extra_query_template_params = self._get_extra_query_template_params(
            table_attributes
        )
        parameters = [
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            self.dag_execution_context.dag_args["name"],
            table_attributes.table_name,
            self.dag_execution_context.execution_date,
            json.dumps(table_attributes.partitions),
            table_attributes.extraction_type,
            extra_query_template_params["load_start_date"],
            extra_query_template_params["load_end_date"],
        ]
        if getattr(self.dag_execution_context, "is_validation", False):
            target_db, target_table = table_attributes.get_validation_write_target()
            parameters.extend(
                [
                    "--target-database-name",
                    target_db,
                    "--target-table-name",
                    target_table,
                ]
            )
        return parameters

    def _get_extra_query_template_params(
        self, table_attributes: TableAttributes
    ) -> dict:
        """
        Resolves per-table ``extra_query_template_params`` for API raw loads.

        Table extra replaces the workflow dict (same as query/CDC). Missing
        ``load_start_date`` / ``load_end_date`` are filled from the DAG
        execution context. The Spark job only substitutes those two keys in
        ``params`` placeholders; other extra keys are ignored.

        The returned dict is a copy so declaration maps are not mutated.
        """
        default_extra_query_template_params = (
            self.dag_execution_context.workflow_args.get(
                "extra_query_template_params", {}
            )
        )
        extra_query_template_params = dict(
            table_attributes.table_customization.get(
                "extra_query_template_params",
                default_extra_query_template_params,
            )
        )
        if "load_start_date" not in extra_query_template_params:
            extra_query_template_params["load_start_date"] = (
                self.dag_execution_context.load_start_date
            )
        if "load_end_date" not in extra_query_template_params:
            extra_query_template_params["load_end_date"] = (
                self.dag_execution_context.load_end_date
            )
        return extra_query_template_params

    def _create_base_load_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            task_id,
            parameters,
            spark_job_prefix=self._get_spark_job_prefix(),
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )

    def _get_spark_job_prefix(self) -> str:
        """
        Returns spark_job_prefix from workflow_args.

        Defaults to 'base' since the CI upload script deploys dags/cross/base/spark_jobs/
        to S3 as spark_jobs/base/ (same as load_cdc_raw, load_postgres_raw).
        """
        return self.dag_execution_context.workflow_args.get("spark_job_prefix", "base")
