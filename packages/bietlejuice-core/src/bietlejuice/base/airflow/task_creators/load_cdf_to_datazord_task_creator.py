from typing import List

from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.datazord_config import (
    resolve_checkpoint_location,
    resolve_include_delete_events,
    resolve_kafka_topic,
    resolve_schema_validation,
)
from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.services.configuration_service import ConfigurationService


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
        datazord_config = self.dag_execution_context.workflow_args["datazord_config"]
        # Use the physical metastore database (e.g. datalake_transactional_entities),
        # not the logical schema from the DAG name (transactional_entities).
        database_name = table_attributes.get_prod_database_name()
        table = table_attributes.table_name
        entity = datazord_config["entity"]
        dag_name = self.dag_execution_context.dag_args["name"]
        workflow_type = self.dag_execution_context.workflow_args.get("type")
        topic = resolve_kafka_topic(
            datazord_config, self.dag_execution_context.environment
        )
        checkpoint_location = resolve_checkpoint_location(
            self.checkpoint_location,
            table,
            workflow_type=workflow_type,
            dag_name=dag_name,
        )
        schema_validation = resolve_schema_validation(datazord_config)
        include_delete_events = resolve_include_delete_events(datazord_config)

        parameters = [
            "--delta-table",
            f"{database_name}.{table}",
            "--key-columns",
            ",".join(key_columns),
            "--kafka-topic",
            topic,
            "--kafka-bootstrap-servers",
            self.kafka_bootstrap_servers,
            "--checkpoint-location",
            checkpoint_location,
            "--entity",
            entity,
            "--schema-validation",
            schema_validation,
        ]
        if include_delete_events:
            parameters.append("--include-delete-events")
        return parameters

    def create_task(
        self, table_attributes: TableAttributes, key_columns: List[str]
    ) -> BaseOperator:
        parameters = self._get_parameters(table_attributes, key_columns)

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            "load-cdf-to-datazord",
            parameters,
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )
