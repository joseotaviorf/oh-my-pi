import sys
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


class TestPublishTableAccess:
    @staticmethod
    def _publish_access_modules(
        mock_sync_secondary, uc_enabled=False, is_emr=False, mock_glue_helper=None
    ):
        mock_uc_helper = mock.MagicMock()
        mock_uc_helper.is_cluster_unity_catalog_enabled.return_value = uc_enabled

        fake_delta_module = mock.MagicMock()
        fake_delta_module.sync_delta_write_to_secondary_catalog = mock_sync_secondary

        fake_uc_module = mock.MagicMock()
        fake_uc_module.UnityCatalogHelper = mock_uc_helper

        mock_runtime = mock.MagicMock()
        mock_runtime.is_emr.return_value = is_emr
        fake_runtime_module = mock.MagicMock()
        fake_runtime_module.RuntimeDetector = mock_runtime

        fake_glue_module = mock.MagicMock()
        fake_glue_module.GlueCatalogHelper = mock_glue_helper or mock.MagicMock()

        return {
            "bietlejuice.base.spark": mock.MagicMock(),
            "bietlejuice.base.spark.delta_secondary_catalog_sync": fake_delta_module,
            "bietlejuice.base.spark.runtime_detector": fake_runtime_module,
            "bietlejuice.base.spark.glue_catalog_helper": fake_glue_module,
            "bietlejuice.base.spark.unity_catalog_helper": fake_uc_module,
            "bietlejuice.base.databricks.table_privileges": mock.MagicMock(),
            "bietlejuice.services.schema_service": mock.MagicMock(),
        }

    def test_secondary_catalog_sync_does_not_log_false_success(self):
        # Arrange — Glue/UC helpers swallow failures; sync returns without raising
        mock_sync_secondary = mock.MagicMock()
        spark = mock.MagicMock()
        spark.catalog.tableExists.return_value = True
        writer = _writer(spark)
        dataframe = mock.MagicMock()
        fqtn = "datalake_observability.profile_table_metrics"
        location = "s3://bucket/datalake_observability/profile_table_metrics"

        # Act
        with (
            mock.patch.dict(
                sys.modules,
                self._publish_access_modules(mock_sync_secondary),
            ),
            mock.patch(
                "bietlejuice.observability.profiling.store_writer.logger"
            ) as mock_logger,
        ):
            writer._publish_table_access(fqtn, location, dataframe)

        # Assert — rely on helper-level logs, not a blanket success message
        mock_sync_secondary.assert_called_once()
        success_logs = [
            call
            for call in mock_logger.info.call_args_list
            if "secondary catalog" in str(call).lower()
        ]
        assert success_logs == []

    def test_secondary_catalog_refresh_failure_is_logged(self):
        # Arrange
        mock_sync_secondary = mock.MagicMock(
            side_effect=RuntimeError("REFRESH TABLE failed")
        )
        spark = mock.MagicMock()
        spark.catalog.tableExists.return_value = True
        writer = _writer(spark)
        dataframe = mock.MagicMock()
        fqtn = "datalake_observability.profile_table_metrics"
        location = "s3://bucket/datalake_observability/profile_table_metrics"

        # Act
        with (
            mock.patch.dict(
                sys.modules,
                self._publish_access_modules(mock_sync_secondary),
            ),
            mock.patch(
                "bietlejuice.observability.profiling.store_writer.logger"
            ) as mock_logger,
        ):
            writer._publish_table_access(fqtn, location, dataframe)

        # Assert — REFRESH TABLE errors still surface; UC grants skipped (UC off)
        mock_logger.error.assert_any_call(
            f"Failed to sync {fqtn} to secondary catalog: REFRESH TABLE failed"
        )

    def test_emr_registers_table_in_glue(self):
        # Arrange — on EMR the secondary catalog is UC, so Glue (what Trino reads)
        # must be registered explicitly or the store stays invisible in Trino/Glue.
        mock_glue_helper = mock.MagicMock()
        spark = mock.MagicMock()
        spark.catalog.tableExists.return_value = True
        writer = _writer(spark)
        dataframe = mock.MagicMock()
        fqtn = "datalake_observability.profile_table_metrics"
        location = "s3://bucket/datalake_observability/profile_table_metrics"

        # Act
        with mock.patch.dict(
            sys.modules,
            self._publish_access_modules(
                mock.MagicMock(), is_emr=True, mock_glue_helper=mock_glue_helper
            ),
        ):
            writer._publish_table_access(fqtn, location, dataframe)

        # Assert — Glue registration invoked with the table's FQN split + Delta format
        mock_glue_helper.sync_table_to_glue.assert_called_once()
        _, kwargs = mock_glue_helper.sync_table_to_glue.call_args
        assert kwargs["database_name"] == DATABASE
        assert kwargs["table_name"] == "profile_table_metrics"
        assert kwargs["table_location"] == location
        assert kwargs["partitions"] == ["year", "month", "day"]
        assert kwargs["format_str"] == "DELTA"

    def test_databricks_does_not_double_register_glue(self):
        # Arrange — on Databricks Glue is the secondary catalog, already synced above,
        # so the explicit EMR-only registration must not fire (no redundant write).
        mock_glue_helper = mock.MagicMock()
        spark = mock.MagicMock()
        spark.catalog.tableExists.return_value = True
        writer = _writer(spark)
        dataframe = mock.MagicMock()
        fqtn = "datalake_observability.profile_table_metrics"
        location = "s3://bucket/datalake_observability/profile_table_metrics"

        # Act
        with mock.patch.dict(
            sys.modules,
            self._publish_access_modules(
                mock.MagicMock(), is_emr=False, mock_glue_helper=mock_glue_helper
            ),
        ):
            writer._publish_table_access(fqtn, location, dataframe)

        # Assert
        mock_glue_helper.sync_table_to_glue.assert_not_called()

    def test_emr_glue_registration_failure_is_logged_and_swallowed(self):
        # Arrange — Glue failure must never break profiling (fail-open, NFR1)
        mock_glue_helper = mock.MagicMock()
        mock_glue_helper.sync_table_to_glue.side_effect = RuntimeError("Glue down")
        spark = mock.MagicMock()
        spark.catalog.tableExists.return_value = True
        writer = _writer(spark)
        dataframe = mock.MagicMock()
        fqtn = "datalake_observability.profile_table_metrics"
        location = "s3://bucket/datalake_observability/profile_table_metrics"

        # Act
        with (
            mock.patch.dict(
                sys.modules,
                self._publish_access_modules(
                    mock.MagicMock(), is_emr=True, mock_glue_helper=mock_glue_helper
                ),
            ),
            mock.patch(
                "bietlejuice.observability.profiling.store_writer.logger"
            ) as mock_logger,
        ):
            writer._publish_table_access(fqtn, location, dataframe)

        # Assert — error logged, exception not propagated
        mock_logger.error.assert_any_call(
            f"Failed to register {fqtn} in Glue: Glue down"
        )
