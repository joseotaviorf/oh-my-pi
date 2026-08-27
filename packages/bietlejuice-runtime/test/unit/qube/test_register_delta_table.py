"""Unit tests for QUBE register_delta_table helpers."""

from unittest.mock import MagicMock

import pytest

from bietlejuice.qube.jobs.common.register_delta_table import (
    _constructed_table_location,
    _full_table_name,
    _is_missing_table_error,
    _resolve_table_location,
    _resolve_table_location_from_metastore,
    _to_trino_s3_location,
)


class TestLocationHelpers:
    def test_to_trino_s3_location(self):
        assert _to_trino_s3_location("s3://bucket/path") == "s3a://bucket/path"
        assert _to_trino_s3_location("s3a://bucket/path") == "s3a://bucket/path"

    def test_constructed_table_location(self):
        location = _constructed_table_location(
            "s3://bucket/qube/db/", "visit_booked_7d"
        )
        assert location == "s3a://bucket/qube/db/visit_booked_7d"

    def test_is_missing_table_error(self):
        assert _is_missing_table_error("No transaction log found for s3a://...")
        assert not _is_missing_table_error("permission denied")

    def test_full_table_name_with_catalog(self):
        assert (
            _full_table_name("qube_measures", "visit_booked_7d", "quintoandar_forno")
            == "quintoandar_forno.qube_measures.visit_booked_7d"
        )

    def test_full_table_name_without_catalog(self):
        assert _full_table_name("qube_measures", "visit_booked_7d", None) == (
            "qube_measures.visit_booked_7d"
        )


class TestResolveTableLocation:
    def test_emr_uses_constructed_path_without_spark_lookup(self):
        spark_ms = MagicMock()
        spark_ms.spark_database_name = "qube_measures"
        spark_ms.database_location = "s3://bucket/qube/measures/"

        location = _resolve_table_location(
            spark=MagicMock(),
            spark_ms=spark_ms,
            table_name="visit_booked_7d",
            current_catalog=None,
            prefer_metastore_lookup=False,
        )

        assert location == "s3a://bucket/qube/measures/visit_booked_7d"

    def test_databricks_prefers_metastore_location(self):
        spark = MagicMock()
        spark.sql.return_value.collect.return_value = [
            ("Location", "s3://bucket/qube/measures/visit_booked_7d")
        ]
        spark_ms = MagicMock()
        spark_ms.spark_database_name = "qube_measures"
        spark_ms.database_location = "s3://bucket/qube/measures/"

        location = _resolve_table_location(
            spark=spark,
            spark_ms=spark_ms,
            table_name="visit_booked_7d",
            current_catalog="quintoandar_forno",
            prefer_metastore_lookup=True,
        )

        assert location == "s3a://bucket/qube/measures/visit_booked_7d"
        spark.sql.assert_called_once_with(
            "DESCRIBE EXTENDED quintoandar_forno.qube_measures.visit_booked_7d"
        )

    def test_metastore_lookup_falls_back_to_constructed_path(self):
        spark = MagicMock()
        spark.sql.side_effect = RuntimeError("metastore unavailable")
        fallback = "s3a://bucket/qube/measures/visit_booked_7d"

        location = _resolve_table_location_from_metastore(
            spark,
            "qube_measures.visit_booked_7d",
            fallback,
        )

        assert location == fallback

    def test_metastore_lookup_reraises_missing_table(self):
        spark = MagicMock()
        spark.sql.side_effect = Exception("TABLE_OR_VIEW_NOT_FOUND")

        with pytest.raises(Exception, match="TABLE_OR_VIEW_NOT_FOUND"):
            _resolve_table_location_from_metastore(
                spark,
                "qube_measures.missing_table",
                "s3a://bucket/fallback",
            )
