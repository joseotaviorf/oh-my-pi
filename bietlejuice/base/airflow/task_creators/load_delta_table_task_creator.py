from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator
import json


class LoadDeltaTableTaskCreator(BaseTaskCreator):
    """Creates the task that loads a delta data from using delta loaders"""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_delta_table"

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        default_extra_query_template_params = self.dag_execution_context.workflow_args.get(
            "extra_query_template_params", {}
        )
        extra_query_template_params = table_attributes.table_customization.get(
            "extra_query_template_params", default_extra_query_template_params
        )

        return [
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            table_attributes.layer.value,
            table_attributes.schema,
            self.dag_execution_context.dag_args["name"],
            table_attributes.table_name,
            json.dumps(table_attributes.partitions),
            self.dag_execution_context.execution_date,
            table_attributes.extraction_type,
            json.dumps(
                self.dag_execution_context.workflow_args.get(
                    "spark_session_configs", {}
                )
            ),
            json.dumps(extra_query_template_params),
        ]

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        if table_attributes.layer == LayerEnum.DW:
            task_id = self.generate_task_id(
                table_attributes, dynamic_template="load-{layer}-{schema}-{table_name}"
            )
        else:
            task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)
