import json

from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes


class ProfilingTaskCreator(BaseTaskCreator):
    """
    Creates the post-load profiling task, which runs on the DAG's shared job
    cluster right after the load and appends fresh-tier observability metrics to
    ``datalake_observability``. Whether it is added to a workflow at all is
    decided by ``BaseWorkflow._check_include_profiling_task`` (the
    ``observability`` declaration block + the runtime kill-switch).
    """

    _TASK_ID_TEMPLATE = "profiling-{layer}-{table_name}"

    DEFAULT_SPARK_JOB_NAME = "profiling"

    def create_task(self, table_attributes: TableAttributes) -> BaseOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(
            self.DEFAULT_SPARK_JOB_NAME, task_id, parameters
        )

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        observability = self.dag_execution_context.workflow_args.get("observability")
        if observability is None:
            dag_enabled = ""  # undeclared: runtime falls back to the global default
            column_checks = False
        else:
            enabled = observability.get("enabled")
            if enabled is None:
                dag_enabled = (
                    ""  # block present but enabled omitted: use global default
                )
            else:
                dag_enabled = str(bool(enabled)).lower()
            column_checks = bool(observability.get("column_checks", False))

        return [
            self.dag_execution_context.environment,
            self.dag_execution_context.execution_date,
            table_attributes.get_prod_database_name(),
            table_attributes.table_name,
            table_attributes.layer.value,
            json.dumps(table_attributes.partitions),
            str(column_checks).lower(),
            dag_enabled,
        ]
