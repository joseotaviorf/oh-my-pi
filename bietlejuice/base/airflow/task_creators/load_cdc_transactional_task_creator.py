from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator
from bietlejuice.base.airflow.database_type_enum import DatabaseTypeEnum


class LoadCDCTransactionalTaskCreator(BaseTaskCreator):
    """Creates the task that loads data from the landing zone of a Change Data Capture (CDC) pipeline into the transactional layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_cdc_transactional"
    SUPPORTED_DATABASE_TYPES = [
        DatabaseTypeEnum.POSTGRES.value,
        DatabaseTypeEnum.MYSQL.value,
    ]

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        partitions = ["year", "month", "day", "hour"]

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
        source_schema = self.dag_execution_context.workflow_args.get(
            "source_schema", "public"
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
            self.dag_execution_context.start_date,
            self.dag_execution_context.end_date,
            str(partitions),
            dbutils_secret_key,
        ]
        return parameters

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)
