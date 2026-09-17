import json

from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.airflow.task_creators.load_task_creator import LoadTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class LoadDeltaTableTaskCreator(LoadTaskCreator):
    """Creates the task that loads a delta data from using delta loaders"""

    _TASK_ID_TEMPLATE = "load-{layer}-{table_name}"
    SPARK_JOB_NAME = "load_delta_table"

    def __init__(self, dag_execution_context, produce_datasets=True):
        super().__init__(
            dag_execution_context,
            produce_datasets,
            storage_format=StorageFormatEnum.DELTA,
        )

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        extra_query_template_params = self._get_extra_query_template_params(
            table_attributes
        )
        merge_on = table_attributes.table_customization.get("merge_on", None)
        when_not_matched_insert_condition = table_attributes.table_customization.get(
            "when_not_matched_insert_condition", None
        )
        when_matched_update_condition = table_attributes.table_customization.get(
            "when_matched_update_condition", None
        )
        when_matched_delete_condition = table_attributes.table_customization.get(
            "when_matched_delete_condition", None
        )
        when_not_matched_by_source_delete_condition = (
            table_attributes.table_customization.get(
                "when_not_matched_by_source_delete_condition", None
            )
        )
        when_matched_operation = table_attributes.table_customization.get(
            "when_matched_operation", None
        )
        when_not_matched_operation = table_attributes.table_customization.get(
            "when_not_matched_operation", None
        )

        parameters = [
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
            json.dumps(merge_on),
            json.dumps(when_not_matched_insert_condition),
            json.dumps(when_matched_update_condition),
            json.dumps(when_matched_delete_condition),
            json.dumps(when_not_matched_by_source_delete_condition),
            json.dumps(when_matched_operation),
            json.dumps(when_not_matched_operation),
            "--column-mapping-mode",
            json.dumps(table_attributes.column_mapping_mode),
            "--table-privileges",
            json.dumps(table_attributes.table_privileges),
            "--table-properties",
            json.dumps(table_attributes.table_properties),
        ]
        parameters.extend(table_attributes.spark_transformation_grade_args())
        if table_attributes.row_filter_column_key:
            parameters.extend(
                [
                    "--row-filter-column-key",
                    table_attributes.row_filter_column_key,
                ]
            )
        if table_attributes.row_filter_function_name:
            parameters.extend(
                [
                    "--row-filter-function-name",
                    table_attributes.row_filter_function_name,
                ]
            )
        validation_target_args: list = []
        if getattr(self.dag_execution_context, "is_validation", False):
            target_db, target_table = table_attributes.get_validation_write_target()
            validation_target_args = [
                "--target-database-name",
                target_db,
                "--target-table-name",
                target_table,
            ]
        return parameters + validation_target_args

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

    def _create_base_load_task(self, table_attributes: TableAttributes) -> BaseOperator:
        if table_attributes.layer == LayerEnum.DW:
            task_id = self.generate_task_id(
                table_attributes, dynamic_template="load-{layer}-{schema}-{table_name}"
            )
        else:
            task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        return self._create_spark_job_task(
            self.SPARK_JOB_NAME,
            task_id,
            parameters,
            execution_timeout_hours=self._get_execution_timeout_hours(table_attributes),
        )
