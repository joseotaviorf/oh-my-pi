from unittest.mock import patch

import pytest

from scripts.services.metadata_file_service import (
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
    @pytest.mark.parametrize(
        "schema",
        ("ops_finance", "ops_ss", "forrent_postcontract"),
    )
    def test_governed_schema_uses_pure_name(self, schema):
        # governed Luigi materialization schemas -> enrich expects the prefixless name
        _validate(schema, schema)  # no exception

    @pytest.mark.parametrize(
        "schema",
        ("ops_finance", "ops_ss", "forrent_postcontract"),
    )
    def test_governed_schema_rejects_datalake_prefix(self, schema):
        with pytest.raises(DatabaseNameMismatchException):
            _validate(f"datalake_{schema}", schema)

    def test_regular_schema_keeps_datalake_prefix(self):
        # non-governed schema is unaffected by the naming convention
        _validate("datalake_sale", "sale")  # no exception

    def test_regular_schema_rejects_pure_name(self):
        with pytest.raises(DatabaseNameMismatchException):
            _validate("sale", "sale")
