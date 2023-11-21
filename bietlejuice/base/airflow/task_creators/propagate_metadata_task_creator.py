from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class PropagateMetadataTaskCreator(BaseTaskCreator):
    """
    Creates the task that calls metadata propagator. This is not necessary for when there is no metadata file for the table,
    and no product database name is configured. That should be determined by the workflow.
    """

    _TASK_ID_TEMPLATE = "propagate-table-metadata-{layer}-{schema}-{table_name}"

    DEFAULT_SPARK_JOB_NAME = "propagate_table_metadata"
    LAYER_TO_PROPAGATOR_SPARK_JOB_MAPPING = {
        LayerEnum.RAW.value: "propagate_raw_tables_metadata"
    }

    def create_task(
        self, table_attributes: TableAttributes
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)
        spark_job_name = self._get_spark_job_name(table_attributes.layer)

        return self._create_spark_job_task(spark_job_name, task_id, parameters)

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        product_database_name = self._get_product_database_name()
        metadata_type = self._get_metadata_type(table_attributes, product_database_name)

        parameters = [
            table_attributes.layer.value,
            metadata_type.value,
            table_attributes.schema,
        ]
        if table_attributes.layer == LayerEnum.RAW:
            parameters += self._get_raw_params(product_database_name)
        parameters.append(table_attributes.table_name)

        return parameters

    def _get_metadata_type(
        self, table_attributes: TableAttributes, product_database_name: str
    ) -> MetadataTypeEnum:
        """
        For every layer other than raw, the only thing to propagate is lineage. For raw, we propagate the full content lineage
        when there is a product database name configured, otherwise only tags.
        """

        if table_attributes.layer != LayerEnum.RAW:
            return MetadataTypeEnum.LINEAGE
        if product_database_name:
            return MetadataTypeEnum.FULL_CONTENT_LINEAGE
        return MetadataTypeEnum.TAGS

    def _get_raw_params(self, product_database_name: str) -> list:
        return [
            self.environment_attributes.dag_args["name"],
            "--product-database-name",
            product_database_name,
            "--table-name",
        ]

    def _get_product_database_name(self) -> str:
        return self.environment_attributes.workflow_args.get(
            "lineage_product_database_name", ""
        )

    def _get_spark_job_name(self, layer: LayerEnum) -> str:
        return self.LAYER_TO_PROPAGATOR_SPARK_JOB_MAPPING.get(
            layer.value, self.DEFAULT_SPARK_JOB_NAME
        )
