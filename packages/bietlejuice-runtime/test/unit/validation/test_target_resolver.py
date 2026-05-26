import pytest

from bietlejuice.validation.target_resolver import (
    CLUSTER_VALIDATION_SCHEMA,
    resolve_validation_target,
    validation_database_location,
)


class TestResolveValidationTarget:
    @pytest.mark.parametrize(
        "prod_database,table,expected_table",
        [
            ("datalake_foo", "bar", "datalake_foo___bar"),
            ("dw_foo", "bar", "dw_foo___bar"),
            ("metric_foo", "bar", "metric_foo___bar"),
            ("core_listing", "fact_x", "core_listing___fact_x"),
            (
                "datalake_databricks_health",
                "daily_cluster_health",
                "datalake_databricks_health___daily_cluster_health",
            ),
        ],
    )
    def test_maps_prod_database_and_table(self, prod_database, table, expected_table):
        schema, validation_table = resolve_validation_target(prod_database, table)

        assert schema == CLUSTER_VALIDATION_SCHEMA
        assert validation_table == expected_table


class TestValidationDatabaseLocation:
    @pytest.mark.parametrize(
        "bucket,prod_database",
        [
            ("test-bucket", "datalake_foo"),
            ("another-bucket", "dw_bar"),
        ],
    )
    def test_s3_prefix(self, bucket, prod_database):
        path = validation_database_location(bucket, prod_database)

        assert path == f"s3a://{bucket}/validation/cluster_validation/{prod_database}/"
