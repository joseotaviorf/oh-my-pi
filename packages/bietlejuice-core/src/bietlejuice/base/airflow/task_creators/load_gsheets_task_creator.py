"""Task creator para ingestão simples de Google Sheets (single-step overwrite).

Cria a task que roda o Spark job `load_gsheets_full_overwrite`, que lê a planilha
e sobrescreve a tabela direto no schema final (clean). Usado pelo
`RawGsheetsIngestionWorkflow` (tipo de DAG `gsheets_ingestion`).
"""

from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator

from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.airflow.task_creators.load_task_creator import LoadTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes

# Defaults do secret da service account de gsheets no Databricks.
# Sobreescrevíveis via workflow_args (gsheets_credentials_scope / gsheets_credentials_key).
_DEFAULT_CREDENTIALS_SCOPE = "quintoandar"
_DEFAULT_CREDENTIALS_KEY = "GOOGLE_SERVICE_ACCOUNT_CREDENTIALS"


class LoadGsheetsTaskCreator(LoadTaskCreator):
    """Cria a task que lê a planilha e sobrescreve a tabela final via Spark job."""

    _TASK_ID_TEMPLATE = "load-gsheets-{table_name}"
    SPARK_JOB_NAME = "load_gsheets_full_overwrite"

    def __init__(self, dag_execution_context, produce_datasets=True):
        super().__init__(
            dag_execution_context,
            produce_datasets,
            storage_format=StorageFormatEnum.PARQUET,
        )

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        """Argumentos posicionais — devem casar com
        ``dags/cross/base/spark_jobs/load_gsheets_full_overwrite.py``."""
        customization = table_attributes.table_customization
        workflow_args = self.dag_execution_context.workflow_args
        source = workflow_args["custom_schema"]

        sheet_id = customization["sheet_id"]
        sheet_name = customization["sheet_name"]
        credentials_key = workflow_args.get(
            "gsheets_credentials_key", _DEFAULT_CREDENTIALS_KEY
        )
        credentials_scope = workflow_args.get(
            "gsheets_credentials_scope", _DEFAULT_CREDENTIALS_SCOPE
        )

        parameters = [
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            source,
            table_attributes.table_name,
            sheet_id,
            sheet_name,
            credentials_key,
            credentials_scope,
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

    def _create_base_load_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)
        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            task_id,
            parameters,
            spark_job_prefix=self.dag_execution_context.workflow_args.get(
                "spark_job_prefix", "base"
            ),
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )
