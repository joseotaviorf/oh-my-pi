from datetime import datetime
from unittest import mock

import pytest

from bietlejuice.observability.profiling import profiling_pipeline as pipeline_module
from bietlejuice.observability.profiling.profiling_pipeline import ProfilingPipeline


def _config_service(kill_switch=True, default_enabled=True, bucket="5a-datalake-forno"):
    service = mock.MagicMock()
    values = {
        "profiling_enabled": kill_switch,
        "profiling_default_enabled": default_enabled,
        "datalake_bucket": bucket,
    }
    service.get_config.side_effect = lambda key: values[key]
    return service


@pytest.fixture
def reader():
    reader = mock.MagicMock()
    reader.last_commit.return_value = {
        "version": 7,
        "operationMetrics": {"numOutputRows": "100"},
    }
    reader.detail.return_value = {
        "numFiles": 3,
        "sizeInBytes": 512,
        "createdAt": "2026-01-01",
        "lastModified": "2026-07-23",
        "partitionColumns": ["year", "month", "day"],
        "clusteringColumns": [],
        "properties": {},
        "tableFeatures": [],
    }
    reader.schema_fields.return_value = [{"name": "id", "type": "bigint"}]
    reader.count.return_value = 100
    reader.partition_specs.return_value = ["year=2026/month=07/day=23"]
    return reader


def _pipeline(config_service, partitions=None, dag_enabled=True):
    return ProfilingPipeline(
        environment="forno",
        run_logical_date="2026-07-23",
        database="dw_rent",
        table="fact_contracts",
        layer="dw",
        partitions=partitions if partitions is not None else ["year", "month", "day"],
        dag_enabled=dag_enabled,
        spark=mock.MagicMock(),
        config_service=config_service,
    )


class TestGating:
    def test_no_ops_when_kill_switch_off(self, reader):
        # Arrange
        pipeline = _pipeline(_config_service(kill_switch=False))
        with (
            mock.patch.object(
                pipeline_module, "DeltaMetadataReader", return_value=reader
            ),
            mock.patch.object(
                pipeline_module, "ObservabilityStoreWriter"
            ) as writer_cls,
        ):
            # Act
            pipeline.run()

        # Assert — nothing collected, nothing written
        reader.detail.assert_not_called()
        writer_cls.assert_not_called()

    def test_no_ops_when_not_opted_in(self, reader):
        # Arrange — Phase 1: default off, DAG did not declare observability
        pipeline = _pipeline(_config_service(default_enabled=False), dag_enabled=None)
        with (
            mock.patch.object(
                pipeline_module, "DeltaMetadataReader", return_value=reader
            ),
            mock.patch.object(
                pipeline_module, "ObservabilityStoreWriter"
            ) as writer_cls,
        ):
            # Act
            pipeline.run()

        # Assert
        writer_cls.assert_not_called()

    def test_runs_when_dag_opts_in(self, reader):
        # Arrange — default off, but the DAG explicitly opts in
        pipeline = _pipeline(_config_service(default_enabled=False), dag_enabled=True)
        with (
            mock.patch.object(
                pipeline_module, "DeltaMetadataReader", return_value=reader
            ),
            mock.patch.object(
                pipeline_module, "ObservabilityStoreWriter"
            ) as writer_cls,
        ):
            # Act
            pipeline.run()

        # Assert
        writer_cls.return_value.append_table_metrics.assert_called_once()


class TestCaptureHappyPath:
    def test_builds_header_and_metrics(self, reader):
        # Arrange
        pipeline = _pipeline(_config_service())
        with (
            mock.patch.object(
                pipeline_module, "DeltaMetadataReader", return_value=reader
            ),
            mock.patch.object(
                pipeline_module, "ObservabilityStoreWriter"
            ) as writer_cls,
        ):
            # Act
            pipeline.run()

        # Assert
        writer = writer_cls.return_value
        table_rows = writer.append_table_metrics.call_args[0][0]
        partition_rows = writer.append_partition_metrics.call_args[0][0]
        assert len(table_rows) == 1
        assert len(partition_rows) == 1
        record = table_rows[0]
        assert record["database"] == "dw_rent"
        assert record["table"] == "fact_contracts"
        assert record["layer"] == "dw"
        assert record["environment"] == "forno"
        assert record["run_logical_date"] == "2026-07-23"
        assert record["collection_method"] == "spark_log"
        assert record["metric_schema_version"] == 1
        assert isinstance(record["profiled_at"], datetime)
        assert record["row_count"] == 100
        # partition parts stamped from the logical date
        assert (record["year"], record["month"], record["day"]) == (2026, 7, 23)

    def test_profiled_delta_version_stamped_on_every_grain(self, reader):
        # Arrange
        pipeline = _pipeline(_config_service())
        with (
            mock.patch.object(
                pipeline_module, "DeltaMetadataReader", return_value=reader
            ),
            mock.patch.object(
                pipeline_module, "ObservabilityStoreWriter"
            ) as writer_cls,
        ):
            # Act
            pipeline.run()

        # Assert — version 7 stamped on every grain
        writer = writer_cls.return_value
        assert (
            writer.append_table_metrics.call_args[0][0][0]["profiled_delta_version"]
            == 7
        )
        assert (
            writer.append_partition_metrics.call_args[0][0][0]["profiled_delta_version"]
            == 7
        )


class TestPartitionsFallback:
    def test_uses_dag_partitions_when_delta_partition_columns_empty(self, reader):
        # Arrange — DESCRIBE DETAIL returns no partition columns; DAG supplies them
        reader.detail.return_value = {
            "numFiles": 3,
            "sizeInBytes": 512,
            "createdAt": "2026-01-01",
            "lastModified": "2026-07-23",
            "partitionColumns": [],
            "clusteringColumns": [],
            "properties": {},
            "tableFeatures": [],
        }
        pipeline = _pipeline(_config_service(), partitions=["year", "month", "day"])
        with (
            mock.patch.object(
                pipeline_module, "DeltaMetadataReader", return_value=reader
            ),
            mock.patch.object(
                pipeline_module, "ObservabilityStoreWriter"
            ) as writer_cls,
        ):
            # Act
            pipeline.run()

        # Assert — partition metrics collected via DAG-declared columns
        writer = writer_cls.return_value
        assert len(writer.append_partition_metrics.call_args[0][0]) == 1
        reader.partition_specs.assert_called_with(
            "dw_rent.fact_contracts", ["year", "month", "day"]
        )


class TestFailOpen:
    def test_collector_exception_is_swallowed(self, reader):
        # Arrange — table collector blows up; the run must not raise and the
        # partition grain (driven by the ``partitions`` arg) still survives.
        pipeline = _pipeline(_config_service(), partitions=["year", "month", "day"])
        with (
            mock.patch.object(
                pipeline_module, "DeltaMetadataReader", return_value=reader
            ),
            mock.patch.object(
                pipeline_module,
                "collect_table_metrics",
                side_effect=RuntimeError("boom"),
            ),
            mock.patch.object(
                pipeline_module, "ObservabilityStoreWriter"
            ) as writer_cls,
        ):
            # Act
            pipeline.run()

        # Assert — table grain dropped, partition grain survives, no exception
        writer = writer_cls.return_value
        assert writer.append_table_metrics.call_args[0][0] == []
        assert len(writer.append_partition_metrics.call_args[0][0]) == 1

    def test_no_write_when_every_read_fails(self, reader):
        # Arrange — every metadata read raises
        reader.last_commit.side_effect = RuntimeError("no log")
        reader.detail.side_effect = RuntimeError("no detail")
        reader.partition_specs.side_effect = RuntimeError("no partitions")
        pipeline = _pipeline(_config_service())
        with (
            mock.patch.object(
                pipeline_module, "DeltaMetadataReader", return_value=reader
            ),
            mock.patch.object(
                pipeline_module, "ObservabilityStoreWriter"
            ) as writer_cls,
        ):
            # Act
            pipeline.run()

        # Assert — nothing captured, so the store writer is never constructed
        writer_cls.assert_not_called()

    def test_run_is_fail_open_when_writer_raises(self, reader):
        # Arrange
        pipeline = _pipeline(_config_service())
        with (
            mock.patch.object(
                pipeline_module, "DeltaMetadataReader", return_value=reader
            ),
            mock.patch.object(
                pipeline_module, "ObservabilityStoreWriter"
            ) as writer_cls,
        ):
            writer_cls.return_value.append_table_metrics.side_effect = RuntimeError(
                "boom"
            )

            # Act / Assert — must not raise (NFR1)
            pipeline.run()


class TestBaseLocation:
    def test_base_location_uses_datalake_bucket(self):
        # Arrange
        pipeline = _pipeline(_config_service())

        # Act
        location = pipeline._base_location()

        # Assert
        assert location == "s3://5a-datalake-forno/datalake_observability"
