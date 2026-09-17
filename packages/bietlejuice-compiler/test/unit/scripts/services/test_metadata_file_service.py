from unittest.mock import patch

import pytest

from bietlejuice.base.db.datalake_metastore_mapping import CONSUMPTION_SCHEMAS
from scripts.services.metadata_file_service import (
    _DB_NAME_FORMULA,
    DatabaseNameMismatchException,
    MetadataFileService,
)


def _validate(database_name: str, custom_schema: str, layer: str = "enrich"):
    """Run _validate_database_name with a stubbed declaration (workflow custom_schema)."""
    table = "test_mat"
    content = {"database_name": database_name}
    table_info = {"dag": f"enrich_luigijr_{table}", "layer": layer, "table_name": table}
    with patch.object(
        MetadataFileService,
        "_load_declaration",
        return_value={"workflow": {"custom_schema": custom_schema}},
    ):
        MetadataFileService._validate_database_name("path/to.yml", content, table_info)


class TestValidateDatabaseNameGovernedSchema:
    @pytest.mark.parametrize("schema", sorted(CONSUMPTION_SCHEMAS))
    def test_governed_schema_uses_pure_name(self, schema):
        # governed Luigi materialization schemas -> enrich expects the prefixless name
        _validate(schema, schema)  # no exception

    @pytest.mark.parametrize("schema", sorted(CONSUMPTION_SCHEMAS))
    def test_governed_schema_rejects_datalake_prefix(self, schema):
        with pytest.raises(DatabaseNameMismatchException):
            _validate(f"datalake_{schema}", schema)

    def test_regular_schema_keeps_datalake_prefix(self):
        # non-governed schema is unaffected by the naming convention
        _validate("datalake_sale", "sale")  # no exception

    def test_regular_schema_rejects_pure_name(self):
        with pytest.raises(DatabaseNameMismatchException):
            _validate("sale", "sale")


class TestValidateDatabaseNameConsumption:
    @pytest.mark.parametrize(
        "schema",
        sorted(CONSUMPTION_SCHEMAS) + ["new_domain"],
    )
    def test_consumption_expects_prefix_free_name(self, schema):
        _validate(schema, schema, layer="consumption")  # no exception

    @pytest.mark.parametrize(
        "schema",
        ("ops_finance", "new_domain"),
    )
    def test_consumption_rejects_datalake_prefix(self, schema):
        with pytest.raises(DatabaseNameMismatchException):
            _validate(f"datalake_{schema}", schema, layer="consumption")

    def test_consumption_rejects_consumption_prefix(self):
        with pytest.raises(DatabaseNameMismatchException):
            _validate("consumption_ops_finance", "ops_finance", layer="consumption")

    @pytest.mark.parametrize("schema", sorted(CONSUMPTION_SCHEMAS) + ["new_domain"])
    def test_consumption_formula_matches_metastore_mapping(self, schema):
        from bietlejuice.base.db.datalake_metastore_mapping import (
            DatalakeMetastoreMapping,
        )
        from bietlejuice.base.pipeline.layer_enum import LayerEnum

        formula_name = _DB_NAME_FORMULA["consumption"].format(schema=schema)
        mapping_name = DatalakeMetastoreMapping(
            schema, "bucket-forno"
        ).get_full_database_name(LayerEnum.CONSUMPTION)
        assert formula_name == mapping_name == schema


class TestValidateDatabaseNameTransformation:
    def test_transformation_clean_grade(self):
        table = "termination"
        content = {"database_name": "transformation_terminator_test_clean"}
        table_info = {
            "dag": "transformation_terminator_test",
            "layer": "transformation",
            "table_name": table,
        }
        with patch.object(
            MetadataFileService,
            "_load_declaration",
            return_value={
                "workflow": {
                    "custom_schema": "terminator_test",
                    "transformation_grade": "clean",
                }
            },
        ):
            MetadataFileService._validate_database_name(
                "path/to.yml", content, table_info
            )

    def test_transformation_rejects_unsuffixed_name(self):
        table = "termination"
        content = {"database_name": "transformation_terminator_test"}
        table_info = {
            "dag": "transformation_terminator_test",
            "layer": "transformation",
            "table_name": table,
        }
        with patch.object(
            MetadataFileService,
            "_load_declaration",
            return_value={
                "workflow": {
                    "custom_schema": "terminator_test",
                    "transformation_grade": "clean",
                }
            },
        ):
            with pytest.raises(DatabaseNameMismatchException):
                MetadataFileService._validate_database_name(
                    "path/to.yml", content, table_info
                )

    def test_transformation_requires_workflow_grade(self):
        table = "termination"
        content = {"database_name": "transformation_terminator_test_clean"}
        table_info = {
            "dag": "transformation_terminator_test",
            "layer": "transformation",
            "table_name": table,
        }
        with patch.object(
            MetadataFileService,
            "_load_declaration",
            return_value={"workflow": {"custom_schema": "terminator_test"}},
        ):
            with pytest.raises(ValueError, match="transformation_grade"):
                MetadataFileService._validate_database_name(
                    "path/to.yml", content, table_info
                )

    def test_transformation_ignores_table_customization_grade(self):
        table = "termination"
        content = {"database_name": "transformation_terminator_test_clean"}
        table_info = {
            "dag": "transformation_terminator_test",
            "layer": "transformation",
            "table_name": table,
        }
        with patch.object(
            MetadataFileService,
            "_load_declaration",
            return_value={
                "workflow": {
                    "custom_schema": "terminator_test",
                    "transformation_grade": "clean",
                    "tables_customization": {
                        table: {"transformation_grade": "curated"},
                    },
                }
            },
        ):
            MetadataFileService._validate_database_name(
                "path/to.yml", content, table_info
            )


class TestGetTableLayerConsumption:
    @pytest.mark.parametrize("schema", sorted(CONSUMPTION_SCHEMAS))
    def test_registered_schemas_are_consumption(self, schema):
        assert MetadataFileService().get_table_layer(schema) == "consumption"

    def test_datalake_prefixed_still_enrich(self):
        assert MetadataFileService().get_table_layer("datalake_ops_finance") == "enrich"
