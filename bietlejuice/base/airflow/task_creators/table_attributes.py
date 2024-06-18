from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TableAttributes:
    def __init__(
        self,
        dag_args: dict,
        workflow_args: dict,
        layer: LayerEnum,
        table_name: str,
        table_customization: dict = None,
    ) -> None:
        self._dag_args = dag_args
        self._workflow_args = workflow_args
        self.layer = layer
        self.table_name = table_name
        self.table_customization = (
            table_customization or self._get_table_customization()
        )
        self.schema = self._get_schema()
        self.extraction_type = self._get_extraction_type()
        self.partitions = self._get_partitions()
        self.has_custom_spark_job = (
            "load_spark_job" in workflow_args
            or "load_spark_job" in self.table_customization
        )

    @staticmethod
    def from_attributes(
        table: "TableAttributes",
        layer: str = None,
        table_name: str = None,
        table_customization: dict = None,
    ) -> None:
        """
        Creates a copy of another TableAttributes, optionally overriding some attributes. This is very common, since workflows often
        have multiple tables with the same attributes, but in different layers.
        """

        return TableAttributes(
            dag_args=table._dag_args,
            workflow_args=table._workflow_args,
            layer=layer or table.layer,
            table_name=table_name or table.table_name,
            table_customization=table_customization or table.table_customization,
        )

    def _get_table_customization(self):
        return self._workflow_args.get("tables_customization", {}).get(
            self.table_name, {}
        )

    def _get_schema(self):
        schema_inferred_from_dag_name = self._dag_args["name"].replace("enrich_", "")
        default_schema = self._workflow_args.get(
            "custom_schema", schema_inferred_from_dag_name
        )
        table_schema = self.table_customization.get("custom_schema", default_schema)
        return table_schema

    def _get_extraction_type(self):
        """
        Follows this order of priority:
        1. Table customization for that specific layer
        2. Table customization
        3. Default for that specific layer
        4. Default
        If none of the above are set, it defaults to "full"
        """

        default_extraction_type = self._workflow_args.get(
            "default_extraction_type", "full"
        )
        if self.layer == LayerEnum.RAW:
            default_extraction_type = self._workflow_args.get(
                "default_raw_extraction_type", default_extraction_type
            )
        elif self.layer == LayerEnum.CLEAN:
            default_extraction_type = self._workflow_args.get(
                "default_clean_extraction_type", default_extraction_type
            )

        table_extraction_type = self.table_customization.get(
            "extraction_type", default_extraction_type
        )
        if self.layer == LayerEnum.RAW:
            table_extraction_type = self.table_customization.get(
                "raw_extraction_type", table_extraction_type
            )
        elif self.layer == LayerEnum.CLEAN:
            table_extraction_type = self.table_customization.get(
                "clean_extraction_type", table_extraction_type
            )
        return table_extraction_type

    def _get_partitions(self):
        """
        Follows this order of priority:
        1. Table customization for that specific layer
        2. Table customization
        3. Default for that specific layer
        4. Default
        If none of the above are set, it defaults to an empty list
        """

        default_partitions = self._workflow_args.get("default_partitions", [])
        if self.layer == LayerEnum.RAW:
            default_partitions = self._workflow_args.get(
                "default_raw_partitions", default_partitions
            )
        elif self.layer == LayerEnum.CLEAN:
            default_partitions = self._workflow_args.get(
                "default_clean_partitions", default_partitions
            )

        table_partitions = self.table_customization.get(
            "partitions", default_partitions
        )
        if self.layer == LayerEnum.RAW:
            table_partitions = self.table_customization.get(
                "raw_partitions", table_partitions
            )
        elif self.layer == LayerEnum.CLEAN:
            table_partitions = self.table_customization.get(
                "clean_partitions", table_partitions
            )

        return table_partitions
