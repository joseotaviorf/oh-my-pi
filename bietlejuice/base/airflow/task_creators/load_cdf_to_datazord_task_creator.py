import json
from typing import List
from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.services.configuration_service import ConfigurationService
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class LoadCDFtoDatazordTaskCreator(BaseTaskCreator):
    """Creates the task that sends the Change Data Feed to the Datazord."""

    SPARK_JOB_NAME = "load_cdf_to_datazord"

    def __init__(
        self,
        dag_execution_context: DagExecutionContext,
        config_service: ConfigurationService,
    ) -> None:
        super().__init__(dag_execution_context)
        self.kafka_bootstrap_servers = config_service.get_config(
            "datazord_kafka_bootstrap_servers"
        )
        self.checkpoint_location = config_service.get_config(
            "datazord_base_checkpoint_location"
        )

    def _get_parameters(
        self, table_attributes: TableAttributes, key_columns: List[str]
    ) -> List[str]:
        schema = table_attributes.schema
        table = table_attributes.table_name
        entity = self.dag_execution_context.workflow_args["datazord_config"]["entity"]
        topic = f"{self.dag_execution_context.environment}_wonka.{entity}"
        checkpoint_location = f"{self.checkpoint_location}/{table}"
        return [
            "--delta-table",
            f"{schema}.{table}",
            "--key-columns",
            ",".join(key_columns),
            "--kafka-topic",
            topic,
            "--kafka-bootstrap-servers",
            self.kafka_bootstrap_servers,
            "--checkpoint-location",
            checkpoint_location,
            # This extra metadata will be added to the "metadata.extra"
            # field of every payload sent to Datazord
            "--extra-metadata",
            json.dumps({"entity": entity}),
        ]

    def create_task(
        self, table_attributes: TableAttributes, key_columns: List[str]
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        parameters = self._get_parameters(table_attributes, key_columns)

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            "load-cdf-to-datazord",
            parameters,
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )
