from typing import Optional

from bietlejuice.base.airflow.enums.criticality_enum import CriticalityEnum
from bietlejuice.base.db.datalake_metastore_mapping import require_transformation_grade
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.validation.target_resolver import (
    get_prod_database_name,
    resolve_validation_target,
)
from bietlejuice.services.dag_metadata_service import DAGMetadataService
from bietlejuice.services.file_service import FileService

_VALID_COLUMN_MAPPING_MODES = {None, "none", "name", "id"}


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
        self.table_privileges = self._get_table_privileges()
        self.table_properties = self._get_table_properties()
        self.column_mapping_mode = self._get_column_mapping_mode()
        self.has_soft_delete = self.get_has_soft_delete()
        self.row_filter_column_key = self.table_customization.get(
            "row_filter_column_key", ""
        )
        self.row_filter_function_name = self._get_row_filter_function_name()
        self.criticality = self._get_criticality()
        self.owner = self._get_owner()

    @property
    def workflow_args(self) -> dict:
        """Read-only access to the workflow declaration args (``type``,
        ``has_hive_sync``, ``sync``, ...)."""
        return self._workflow_args

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

    def _get_table_properties(self):
        """
        Get's proeprties from table customization if don't
        returns an empty dict.
        """
        table_properties = self.table_customization.get("table_properties", {})

        return table_properties

    def _get_table_privileges(self):
        """
        Follows this order of priority:
        1. Table customization for that specific layer
        2. Table customization
        3. Default for that specific layer
        4. Default
        If none of the above are set, it defaults to None
        """

        default_table_privileges = self._workflow_args.get(
            "default_table_privileges", None
        )
        if self.layer == LayerEnum.RAW:
            default_table_privileges = self._workflow_args.get(
                "default_raw_table_privileges", default_table_privileges
            )
        elif self.layer == LayerEnum.CLEAN:
            default_table_privileges = self._workflow_args.get(
                "default_clean_table_privileges", default_table_privileges
            )

        table_privileges = self.table_customization.get(
            "table_privileges", default_table_privileges
        )
        if self.layer == LayerEnum.RAW:
            table_privileges = self.table_customization.get(
                "raw_table_privileges", table_privileges
            )
        elif self.layer == LayerEnum.CLEAN:
            table_privileges = self.table_customization.get(
                "clean_table_privileges", table_privileges
            )

        return table_privileges

    def _get_column_mapping_mode(self):
        mode = self.table_customization.get("column_mapping_mode")
        if mode not in _VALID_COLUMN_MAPPING_MODES:
            raise ValueError(
                f"Invalid column_mapping_mode '{mode}'. "
                f"Valid values: {_VALID_COLUMN_MAPPING_MODES}"
            )
        return mode

    def _get_row_filter_function_name(self) -> str:
        self.row_filter = self.table_customization.get("row_filter", "")
        if self.row_filter == "has_3p_access":
            return "data_governance_policies.has_3p_access_control_row_filter"

        return ""

    def _get_criticality(self) -> str:
        declared = self.table_customization.get("criticality") or self._dag_args.get(
            "criticality"
        )
        return CriticalityEnum.parse(declared, context=f"table {self.table_name!r}")

    def _get_owner(self) -> Optional[str]:
        """This table's own ``owner:`` from its metadata file, for auto-tagging
        the JiraOps alert on failure (``JiraOpsCallback``) -- read once at DAG
        build time, same as ``criticality``, rather than re-reading the YAML at
        alert time.

        Best-effort only: this is a cosmetic alert tag, not a data contract, so
        any lookup/IO failure (metadata file missing, DAG path unresolvable in
        a test/local context) degrades to ``None`` rather than breaking DAG
        parsing.
        """
        try:
            paths = DAGMetadataService.get_dag_metadata_file(
                self._dag_args["name"], self.layer.value, self.table_name
            )
            if not paths:
                return None
            metadata = FileService.get_dict_from_yaml_file(paths[0])
        except OSError:
            return None
        owner = metadata.get("owner") if isinstance(metadata, dict) else None
        return owner or None

    def get_has_soft_delete(self) -> bool:
        """
        Follows this order of priority:
        1. Table customization for that specific layer
        2. Workflow args
        If none of the above are set, or the informed value is different from True, it defaults to False
        """

        has_soft_delete = self._workflow_args.get("has_soft_delete", False)
        table_has_soft_delete = self.table_customization.get(
            "has_soft_delete", has_soft_delete
        )

        if isinstance(table_has_soft_delete, str):
            return table_has_soft_delete.lower() == "true"
        return bool(table_has_soft_delete)

    @property
    def transformation_grade(self) -> Optional[str]:
        return self._workflow_args.get("transformation_grade")

    def spark_transformation_grade_args(self) -> list[str]:
        if self.layer != LayerEnum.TRANSFORMATION:
            return []
        grade = require_transformation_grade(self.transformation_grade)
        return ["--transformation-grade", grade]

    def get_prod_database_name(self) -> str:
        return get_prod_database_name(
            self.layer,
            self.schema,
            transformation_grade=self.transformation_grade,
        )

    def get_validation_write_target(self) -> tuple[str, str]:
        return resolve_validation_target(self.get_prod_database_name(), self.table_name)
