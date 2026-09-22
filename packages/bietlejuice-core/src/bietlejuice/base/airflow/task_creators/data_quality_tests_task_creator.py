from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.platform_resolver import resolve_platforms
from bietlejuice.services.configuration_service import ConfigurationService


class DataQualityTestsTaskCreator(BaseTaskCreator):
    """
    Creates the task that execute data quality tests. This is not necessary for when there is no tests. That should be
    determined by the workflow.
    """

    _TASK_ID_TEMPLATE = "data-quality-tests-{layer}-{table_name}"

    DEFAULT_SPARK_JOB_NAME = "data_quality_tests"

    def __init__(
        self,
        dag_execution_context: DagExecutionContext,
        config_service: ConfigurationService,
    ) -> None:
        super().__init__(dag_execution_context)
        self.inmetro_bucket = config_service.get_config("inmetro_bucket")

    def create_task(self, table_attributes: TableAttributes) -> BaseOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        task = self._create_spark_job_task(
            self.DEFAULT_SPARK_JOB_NAME, task_id, parameters
        )
        # JiraOpsCallback.task_failure_alert prefers params["criticality"] over the DAG's, so a
        # DQ failure on a table declared Critical pages P1 just like its load task does.
        task.params.update({"criticality": table_attributes.criticality})
        return task

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        # DataHub platforms this table's DQ should reach (databricks+glue always,
        # trino iff hive-synced) -- passed comma-joined to the spark job.
        platforms = resolve_platforms(
            table_attributes.workflow_args.get("type"),
            table_attributes.workflow_args,
            table_attributes.table_customization,
        )

        parameters = [
            self.dag_execution_context.environment,
            self.dag_execution_context.execution_date,
            self.inmetro_bucket,
            table_attributes.layer.value,
            self.dag_execution_context.dag_args["name"],
            table_attributes.table_name,
            "",  # Tree path. Spark job should be refactored to remove this parameter, eventually
        ]

        # Pass platforms as a NAMED flag, never a trailing positional. On EMR the
        # empty tree-path arg above is dropped from the spark-submit shell command;
        # a positional platforms value would then slide into ``intermediate_path``
        # and break the job (DQ config not found). A named flag is matched by name,
        # immune to the dropped-empty shift. Databricks preserves the arg list, so
        # both engines behave the same.
        if platforms:
            parameters += ["--platforms", ",".join(platforms)]

        return parameters
