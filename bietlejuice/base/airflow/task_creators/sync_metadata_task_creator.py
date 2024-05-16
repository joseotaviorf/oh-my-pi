from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class SyncMetadataTaskCreator(BaseTaskCreator):
    """
    Creates the task that does 3 things:
        - Sync table structure metadata to Hive
        - Sync table partitions to Hive
        - Sync table lineage and metadata to metadata propagator.
    """

    _TASK_ID_TEMPLATE = "sync-metadata-{layer}-{table_name}"

    SPARK_JOB_NAME = "sync_metadata"

    def create_task(
        self, table_attributes: TableAttributes, bypass_task: str = None
    ) -> QuintoAndarDatabricksCheckJobTaskOperator:
        task_id = self.generate_task_id(table_attributes)
        parameters = self._get_parameters(table_attributes)

        if bypass_task:
            parameters.append(bypass_task)

        return self._create_spark_job_task(self.SPARK_JOB_NAME, task_id, parameters)

    def _get_parameters(self, table_attributes: TableAttributes) -> list:
        product_database_name = self._get_product_database_name()
        metadata_type = self._get_metadata_type(table_attributes, product_database_name)

        parameters = [
            self.dag_execution_context.bucket,
            table_attributes.layer.value,
            table_attributes.schema,
            "--table-name",
            table_attributes.table_name,
            metadata_type.value,
            self.dag_execution_context.dag_args["name"],
        ]
        if table_attributes.layer == LayerEnum.RAW:
            parameters += self._get_raw_params(product_database_name)
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
        return ["--product-database-name", product_database_name]

    def _get_product_database_name(self) -> str:
        return self.dag_execution_context.workflow_args.get(
            "lineage_product_database_name", ""
        )
