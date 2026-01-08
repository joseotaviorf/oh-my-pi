"""Unit tests for DeltaCDFReader."""

from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.services.cdf_services.cdf_to_kafka.stream_reader import DeltaCDFReader


@pytest.fixture
def spark_session_mock():
    return MagicMock()


@pytest.fixture
def delta_table():
    return "db.feature_set__latest"


class TestDeltaCDFReaderValidateTable:
    """Tests for DeltaCDFReader.validate_table method."""

    def test_raises_error_when_table_does_not_exist(
        self, spark_session_mock, delta_table
    ):
        """Test that ValueError is raised when table does not exist."""
        spark_session_mock.catalog.tableExists.return_value = False

        reader = DeltaCDFReader(
            spark=spark_session_mock,
            delta_table=delta_table,
        )

        with pytest.raises(ValueError, match="does not exist"):
            reader.validate_table()

    def test_raises_error_when_cdf_not_enabled(self, spark_session_mock, delta_table):
        """Test that ValueError is raised when CDF is not enabled."""
        spark_session_mock.catalog.tableExists.return_value = True

        mock_row = MagicMock()
        mock_row.__str__ = lambda self: "some_property = some_value"
        spark_session_mock.sql.return_value.collect.return_value = [mock_row]

        reader = DeltaCDFReader(
            spark=spark_session_mock,
            delta_table=delta_table,
        )

        with pytest.raises(ValueError, match="Change Data Feed is not enabled"):
            reader.validate_table()

    def test_succeeds_when_table_exists_and_cdf_enabled(
        self, spark_session_mock, delta_table
    ):
        """Test that validation succeeds when table exists and CDF is enabled."""
        spark_session_mock.catalog.tableExists.return_value = True

        mock_row = MagicMock()
        mock_row.__str__ = lambda self: "delta.enableChangeDataFeed = true"
        spark_session_mock.sql.return_value.collect.return_value = [mock_row]

        reader = DeltaCDFReader(
            spark=spark_session_mock,
            delta_table=delta_table,
        )

        reader.validate_table()

        spark_session_mock.catalog.tableExists.assert_called_once_with(delta_table)


class TestDeltaCDFReaderPrepareCdfStream:
    """Tests for DeltaCDFReader.prepare_cdf_stream method."""

    @patch("bietlejuice.services.cdf_services.cdf_to_kafka.stream_reader.config")
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.stream_reader.drop_partition_columns"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.stream_reader.filter_cdf_events"
    )
    def test_filters_and_cleans_cdf_stream(
        self,
        mock_filter,
        mock_drop,
        mock_config,
        spark_session_mock,
        delta_table,
    ):
        """Test that prepare_cdf_stream filters and cleans the stream."""
        mock_config.use_schema_registry = False
        mock_cdf = MagicMock()
        mock_filtered = MagicMock()
        mock_cleaned = MagicMock()

        mock_filter.return_value = mock_filtered
        mock_drop.return_value = mock_cleaned

        mock_stream_builder = MagicMock()
        spark_session_mock.readStream.format.return_value = mock_stream_builder
        mock_stream_builder.option.return_value = mock_stream_builder
        mock_stream_builder.table.return_value = mock_cdf

        reader = DeltaCDFReader(
            spark=spark_session_mock,
            delta_table=delta_table,
        )

        result_df, schema_id = reader.prepare_cdf_stream(kafka_topic="test-topic")

        mock_filter.assert_called_once_with(mock_cdf)
        mock_drop.assert_called_once_with(mock_filtered)
        assert result_df == mock_cleaned
        assert schema_id is None

    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.stream_reader.register_schema_for_dataframe"
    )
    @patch("bietlejuice.services.cdf_services.cdf_to_kafka.stream_reader.config")
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.stream_reader.drop_partition_columns"
    )
    @patch(
        "bietlejuice.services.cdf_services.cdf_to_kafka.stream_reader.filter_cdf_events"
    )
    def test_registers_schema_when_registry_enabled(
        self,
        mock_filter,
        mock_drop,
        mock_config,
        mock_register_schema,
        spark_session_mock,
        delta_table,
    ):
        """Test that schema is registered when use_schema_registry is True."""
        mock_config.use_schema_registry = True
        mock_cleaned = MagicMock()
        mock_drop.return_value = mock_cleaned
        mock_register_schema.return_value = 123

        mock_stream_builder = MagicMock()
        spark_session_mock.readStream.format.return_value = mock_stream_builder
        mock_stream_builder.option.return_value = mock_stream_builder
        mock_stream_builder.table.return_value = MagicMock()

        schema_registry_url = "http://registry:8081"
        schema_registry_api_key = "api_key"
        schema_registry_api_secret = "api_secret"

        reader = DeltaCDFReader(
            spark=spark_session_mock,
            delta_table=delta_table,
            schema_registry_url=schema_registry_url,
            schema_registry_api_key=schema_registry_api_key,
            schema_registry_api_secret=schema_registry_api_secret,
        )

        result_df, schema_id = reader.prepare_cdf_stream(kafka_topic="test-topic")

        mock_register_schema.assert_called_once_with(
            dataframe=mock_cleaned,
            topic="test-topic",
            delta_table=delta_table,
            schema_registry_url=schema_registry_url,
            schema_registry_api_key=schema_registry_api_key,
            schema_registry_api_secret=schema_registry_api_secret,
        )
        assert schema_id == 123
