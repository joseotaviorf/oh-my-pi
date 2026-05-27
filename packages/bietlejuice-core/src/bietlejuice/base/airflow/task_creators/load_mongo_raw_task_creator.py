import json

from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.airflow.task_creators.load_task_creator import LoadTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes


class LoadMongoRawTaskCreator(LoadTaskCreator):
    """Creates the task that extracts data from a MongoDB table and sink into the raw layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_mongo_raw"

    def __init__(self, dag_execution_context, produce_datasets=True):
        super().__init__(
            dag_execution_context,
            produce_datasets,
            storage_format=StorageFormatEnum.JSON,
        )

    def _create_base_load_task(self, table_attributes: TableAttributes) -> BaseOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            task_id,
            parameters,
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )

    def _get_load_options(self, table_attributes: TableAttributes) -> str:
        default_load_options = self.dag_execution_context.workflow_args.get(
            "load_options", {}
        )
        table_load_options = table_attributes.table_customization.get(
            "load_options", default_load_options
        )
        return json.dumps(table_load_options)

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        date_filter_column = table_attributes.table_customization.get(
            "date_filter_column", ""
        )
        dbutils_secret_key = self.dag_execution_context.workflow_args.get(
            "dbutils_secret_key", f"{table_attributes.schema.upper()}_DB"
        )
        dbutils_secret_scope = self.dag_execution_context.workflow_args.get(
            "dbutils_secret_scope", "quintoandar"
        )
        load_options = self._get_load_options(table_attributes)

        parameters = [
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            table_attributes.schema,
            table_attributes.table_name,
            table_attributes.extraction_type,
            str(table_attributes.partitions),
            date_filter_column,
            dbutils_secret_key,
            self.dag_execution_context.execution_date,
            load_options,
            dbutils_secret_scope,
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
        parameters.extend(
            ["--table-privileges", json.dumps(table_attributes.table_privileges)]
        )
        return parameters
