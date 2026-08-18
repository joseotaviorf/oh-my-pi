from unittest import mock

from bietlejuice.observability.profiling.store_schemas import TABLE_METRICS_SCHEMA
from bietlejuice.observability.profiling.store_writer import (
    DATABASE,
    ObservabilityStoreWriter,
)

_SCHEMA_FIELDS = {field.name for field in TABLE_METRICS_SCHEMA.fields}


def _writer(spark):
    return ObservabilityStoreWriter(spark, "s3://bucket/datalake_observability/")


class TestProject:
    def test_keeps_only_schema_fields_by_name(self):
        # Arrange — record has an extra key and is missing most schema fields
        record = {"database": "db", "table": "t", "not_in_schema": "drop me"}

        # Act
        projected = ObservabilityStoreWriter._project(record, TABLE_METRICS_SCHEMA)

        # Assert — extras dropped, missing -> None, exact schema field set
        assert set(projected) == _SCHEMA_FIELDS
        assert "not_in_schema" not in projected
        assert projected["database"] == "db"
        assert projected["row_count"] is None


@mock.patch.object(ObservabilityStoreWriter, "_publish_table_access")
class TestAppend:
    def test_empty_records_do_not_write(self, _publish_access):
        # Arrange
        spark = mock.MagicMock()

        # Act
        count = _writer(spark).append_table_metrics([])

        # Assert
        assert count == 0
        spark.createDataFrame.assert_not_called()
        _publish_access.assert_not_called()

    @mock.patch(
        "bietlejuice.observability.profiling.store_writer.DeltaTable.isDeltaTable",
        return_value=False,
    )
    def test_append_projects_and_writes_delta(self, _is_delta, _publish_access):
        # Arrange
        spark = mock.MagicMock()
        spark.catalog.tableExists.return_value = False
        records = [{"database": "db", "table": "t", "not_in_schema": "x"}]

        # Act
        count = _writer(spark).append_table_metrics(records)

        # Assert
        assert count == 1
        rows, schema = spark.createDataFrame.call_args[0]
        assert schema is TABLE_METRICS_SCHEMA
        assert set(rows[0]) == _SCHEMA_FIELDS
        assert rows[0]["database"] == "db"
        spark.createDataFrame.return_value.write.format.assert_called_with("delta")
        spark.sql.assert_any_call(f"CREATE DATABASE IF NOT EXISTS `{DATABASE}`")
        _publish_access.assert_called_once()

    @mock.patch(
        "bietlejuice.observability.profiling.store_writer.DeltaTable.isDeltaTable",
        return_value=True,
    )
    def test_append_registers_existing_delta_location_on_emr(
        self, _is_delta, _publish_access
    ):
        # Arrange — S3 already has Delta data (e.g. from Databricks), EMR catalog empty
        spark = mock.MagicMock()
        spark.catalog.tableExists.side_effect = [False, True]
        records = [{"database": "db", "table": "t"}]

        # Act
        count = _writer(spark).append_table_metrics(records)

        # Assert
        assert count == 1
        spark.sql.assert_any_call(
            "CREATE TABLE IF NOT EXISTS `datalake_observability`.`profile_table_metrics` "
            "USING DELTA LOCATION "
            "'s3://bucket/datalake_observability/profile_table_metrics'"
        )
        spark.createDataFrame.return_value.write.format.return_value.mode.return_value.option.return_value.insertInto.assert_called_once_with(
            "datalake_observability.profile_table_metrics"
        )
        _publish_access.assert_called_once()

    @mock.patch(
        "bietlejuice.observability.profiling.store_writer.DeltaTable.isDeltaTable",
        return_value=True,
    )
    def test_append_uses_insert_into_when_table_already_registered(
        self, _is_delta, _publish_access
    ):
        # Arrange
        spark = mock.MagicMock()
        spark.catalog.tableExists.return_value = True
        records = [{"database": "db", "table": "t"}]

        # Act
        count = _writer(spark).append_table_metrics(records)

        # Assert
        assert count == 1
        register_calls = [
            call
            for call in spark.sql.call_args_list
            if "CREATE TABLE IF NOT EXISTS" in str(call)
        ]
        assert register_calls == []
        spark.createDataFrame.return_value.write.format.return_value.mode.return_value.option.return_value.insertInto.assert_called_once_with(
            "datalake_observability.profile_table_metrics"
        )
        _publish_access.assert_called_once()

    @mock.patch(
        "bietlejuice.observability.profiling.store_writer.DeltaTable.isDeltaTable",
        return_value=True,
    )
    def test_append_uses_insert_into_when_delta_exists_but_catalog_empty(
        self, _is_delta, _publish_access
    ):
        # Arrange — delta at location; catalog still empty after ensure (race guard)
        spark = mock.MagicMock()
        spark.catalog.tableExists.return_value = False
        records = [{"database": "db", "table": "t"}]

        # Act
        count = _writer(spark).append_table_metrics(records)

        # Assert — must not call saveAsTable on non-empty location
        assert count == 1
        write_chain = spark.createDataFrame.return_value.write.format.return_value
        write_chain.mode.return_value.option.return_value.insertInto.assert_called_once_with(
            "datalake_observability.profile_table_metrics"
        )
        save_as_table = write_chain.mode.return_value.option.return_value.partitionBy
        save_as_table.assert_not_called()
        _publish_access.assert_called_once()
