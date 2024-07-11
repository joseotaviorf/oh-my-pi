from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.services.configuration_service import ConfigurationService
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator

from typing import List


class LoadDMSCDCCleanTaskCreator(BaseTaskCreator):
    """Creates the task that loads data from the raw layer of a Change Data Capture (CDC) pipeline into the clean layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_dms_cdc_clean"

    def __init__(
        self,
        dag_execution_context: DagExecutionContext,
        config_service: ConfigurationService,
    ) -> None:
        super().__init__(dag_execution_context)
        self.data_documentation_bucket = config_service.get_config(
            "data_documentation_bucket"
        )

    def _get_parameters(self, table_attributes: TableAttributes) -> List:
        clean_primary_keys = ",".join(
            table_attributes.table_customization.get("clean_primary_keys", [])
        )

        return [
            self.dag_execution_context.dag_args["name"],
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            self.data_documentation_bucket,
            table_attributes.schema,
            table_attributes.table_name,
            self.dag_execution_context.load_start_date,
            self.dag_execution_context.load_end_date,
            clean_primary_keys,
        ]

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)
