import json
from typing import List

from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.load_task_creator import LoadTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.services.configuration_service import ConfigurationService


class LoadDMSCDCCleanTaskCreator(LoadTaskCreator):
    """Creates the task that loads data from the raw layer of a Change Data Capture (CDC) pipeline into the clean layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_dms_cdc_clean"

    def __init__(
        self,
        dag_execution_context: DagExecutionContext,
        config_service: ConfigurationService,
        produce_datasets: bool = True,
    ) -> None:
        super().__init__(
            dag_execution_context,
            produce_datasets,
            storage_format=StorageFormatEnum.DELTA,
        )
        self.data_documentation_bucket = config_service.get_config(
            "data_documentation_bucket"
        )

    def _get_parameters(self, table_attributes: TableAttributes) -> List:
        clean_primary_keys = ",".join(
            table_attributes.table_customization.get("clean_primary_keys", [])
        )

        parameters = [
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
