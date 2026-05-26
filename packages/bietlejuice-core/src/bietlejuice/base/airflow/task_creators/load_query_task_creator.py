import json

from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.airflow.task_creators.load_task_creator import LoadTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class LoadQueryTaskCreator(LoadTaskCreator):
    """Creates the task that loads data into the enrich layer."""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"

    def __init__(self, dag_execution_context, produce_datasets=True):
        super().__init__(
            dag_execution_context,
            produce_datasets,
            storage_format=StorageFormatEnum.PARQUET,
        )

    def _create_base_load_task(self, table_attributes: TableAttributes) -> BaseOperator:
        spark_job_name = f"load_table_{table_attributes.extraction_type}"

        if table_attributes.layer == LayerEnum.DW:
            task_id = self.generate_task_id(
                table_attributes, dynamic_template="load-{layer}-{schema}-{table_name}"
            )
        else:
            task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(
            spark_job_name,
            task_id,
            parameters,
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        parameters = [
            self.dag_execution_context.environment,
            self.dag_execution_context.bucket,
            table_attributes.layer.value,
            table_attributes.schema,
            table_attributes.schema,
            self.dag_execution_context.dag_args["name"],
            table_attributes.table_name,
            str(table_attributes.partitions),
            self.dag_execution_context.execution_date,
            json.dumps(
                self.dag_execution_context.workflow_args.get(
                    "spark_session_configs", {}
                )
            ),
            json.dumps(self._get_extra_query_template_params(table_attributes)),
            "",
            "",
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

    def _get_extra_query_template_params(
        self, table_attributes: TableAttributes
    ) -> dict:
        default_extra_query_template_params = (
            self.dag_execution_context.workflow_args.get(
                "extra_query_template_params", {}
            )
        )
        extra_query_template_params = table_attributes.table_customization.get(
            "extra_query_template_params", default_extra_query_template_params
        )
        if "load_start_date" not in extra_query_template_params:
            extra_query_template_params["load_start_date"] = (
                self.dag_execution_context.load_start_date
            )
        if "load_end_date" not in extra_query_template_params:
            extra_query_template_params["load_end_date"] = (
                self.dag_execution_context.load_end_date
            )

        return extra_query_template_params
