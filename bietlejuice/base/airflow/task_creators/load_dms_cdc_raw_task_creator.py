import json
from typing import List

from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.airflow.task_creators.load_task_creator import LoadTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes


class LoadDMSCDCRawTaskCreator(LoadTaskCreator):
    """Creates the task that loads data from the DMS bucket of a Change Data Capture (CDC) pipeline into the raw layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_dms_cdc_raw"

    def __init__(self, dag_execution_context, produce_datasets=True):
        super().__init__(
            dag_execution_context,
            produce_datasets,
            storage_format=StorageFormatEnum.DELTA,
        )

    def _get_parameters(self, table_attributes: TableAttributes) -> List:
        primary_keys = ",".join(
            table_attributes.table_customization.get("raw_primary_keys", [])
        )

        return [
            self.dag_execution_context.environment,
            self.dag_execution_context.incoming_bucket,
            self.dag_execution_context.bucket,
            table_attributes.schema,
            table_attributes.table_name,
            self.dag_execution_context.load_start_date,
            self.dag_execution_context.load_end_date,
            primary_keys,
            "--table-privileges",
            json.dumps(table_attributes.table_privileges),
        ]

    def _create_base_load_task(self, table_attributes: TableAttributes) -> BaseOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            task_id,
            parameters,
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )
