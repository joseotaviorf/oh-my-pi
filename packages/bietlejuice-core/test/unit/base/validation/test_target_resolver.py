import pytest

from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.validation.target_resolver import (
    CLUSTER_VALIDATION_SCHEMA,
    get_prod_database_name,
    managed_table_fqn,
    resolve_validation_target,
    validation_database_location,
    validation_dw_database_location,
)


class TestManagedTableFqn:
    def test_prod_when_no_validation_target(self):
        assert managed_table_fqn("datalake_foo", "bar") == "datalake_foo.bar"

    def test_validation_target_when_set(self):
        assert (
            managed_table_fqn(
                "datalake_foo",
                "bar",
                "cluster_validation",
                "datalake_foo___bar",
            )
            == "cluster_validation.datalake_foo___bar"
        )


class TestResolveValidationTarget:
    @pytest.mark.parametrize(
        "prod_database,table,expected_table",
        [
            ("datalake_foo", "bar", "datalake_foo___bar"),
            ("dw_foo", "bar", "dw_foo___bar"),
            ("metric_foo", "bar", "metric_foo___bar"),
            ("core_listing", "fact_x", "core_listing___fact_x"),
        ],
    )
    def test_maps_prod_database_and_table(self, prod_database, table, expected_table):
        schema, validation_table = resolve_validation_target(prod_database, table)

        assert schema == CLUSTER_VALIDATION_SCHEMA
        assert validation_table == expected_table


class TestGetProdDatabaseName:
    def test_dw_staging_uses_dw_metastore_mapping(self):
        assert get_prod_database_name(LayerEnum.DW_STAGING, "foo").endswith("_staging")

    @pytest.mark.parametrize(
        "layer,schema,expected",
        [
            (LayerEnum.TRANSACTIONAL, "payments", "datalake_payments_transactional"),
            (LayerEnum.RAW, "payments", "datalake_payments_raw"),
            (LayerEnum.CLEAN, "payments", "datalake_payments_clean"),
            (LayerEnum.ENRICH, "payments", "datalake_payments"),
            (LayerEnum.CORE, "payments", "payments"),
            (LayerEnum.DW, "payments", "dw_payments"),
            (LayerEnum.METRIC, "payments", "metric_payments"),
            (LayerEnum.REVERSE, "payments", "reverse_payments"),
            (LayerEnum.QUBE, "dimensions", "qube_dimensions"),
        ],
    )
    def test_all_layers_resolve_prod_database_name(self, layer, schema, expected):
        assert get_prod_database_name(layer, schema) == expected

    def test_transformation_requires_grade(self):
        with pytest.raises(ValueError, match="transformation_grade"):
            get_prod_database_name(LayerEnum.TRANSFORMATION, "terminator_test")

    def test_transformation_uses_grade_suffix(self):
        assert (
            get_prod_database_name(
                LayerEnum.TRANSFORMATION,
                "terminator_test",
                transformation_grade="clean",
            )
            == "transformation_terminator_test_clean"
        )


class TestValidationDatabaseLocation:
    def test_under_validation_prefix(self):
        path = validation_database_location("prod-datalake", "datalake_foo")

        assert path == "s3a://prod-datalake/validation/cluster_validation/datalake_foo/"

    def test_dw_uses_s3_scheme(self):
        path = validation_dw_database_location("prod-datalake", "dw_foo")

        assert path == "s3://prod-datalake/validation/cluster_validation/dw_foo/"
