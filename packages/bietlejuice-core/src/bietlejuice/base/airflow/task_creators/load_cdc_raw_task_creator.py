import json

from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.enums.database_type_enum import DatabaseTypeEnum
from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.airflow.task_creators.load_task_creator import LoadTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes


class LoadCDCRawTaskCreator(LoadTaskCreator):
    """Creates the task that loads data from the transactional layer of a Change Data Capture (CDC) pipeline into the raw layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_cdc_raw"
    SUPPORTED_DATABASE_TYPES = [
        DatabaseTypeEnum.POSTGRES.value,
        DatabaseTypeEnum.MYSQL.value,
    ]

    def __init__(self, dag_execution_context, produce_datasets=True):
        super().__init__(
            dag_execution_context,
            produce_datasets,
            storage_format=StorageFormatEnum.DELTA,
        )

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        if "database_type" not in self.dag_execution_context.workflow_args:
            raise ValueError(
                f"database_type is required in workflow_args for CDC DAGs. Supported types are {self.SUPPORTED_DATABASE_TYPES}"
            )
        database_type = self.dag_execution_context.workflow_args["database_type"]
        if database_type not in self.SUPPORTED_DATABASE_TYPES:
            raise ValueError(
                f"Unsupported database type {database_type} for CDC. Supported types are {self.SUPPORTED_DATABASE_TYPES}"
            )

        source_database = self.dag_execution_context.workflow_args.get(
            "source_database", table_attributes.schema
        )
        default_source_schema = self.dag_execution_context.workflow_args.get(
            "source_schema", "public"
        )
        source_schema = table_attributes.table_customization.get(
            "source_schema", default_source_schema
        )
        primary_keys = ",".join(
            table_attributes.table_customization.get("raw_primary_keys", [])
        )
        dbutils_secret_key = self.dag_execution_context.workflow_args.get(
            "dbutils_secret_key", f"{table_attributes.schema.upper()}_DB"
        )

        parameters = [
            self.dag_execution_context.environment,
            self.dag_execution_context.incoming_bucket,
            self.dag_execution_context.bucket,
            database_type,
            source_database,
            source_schema,
            table_attributes.schema,
            table_attributes.table_name,
            self.dag_execution_context.load_start_date,
            self.dag_execution_context.load_end_date,
            primary_keys if primary_keys else "None",
            dbutils_secret_key,
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

    def _create_base_load_task(self, table_attributes: TableAttributes) -> BaseOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            task_id,
            parameters,
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )
