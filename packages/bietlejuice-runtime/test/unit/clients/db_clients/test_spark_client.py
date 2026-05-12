from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.clients.db_clients import SparkClient


class TestSparkClient:
    def test_conn(self, mocked_spark_client):
        # act
        start_conn = mocked_spark_client._session

        # assert
        assert start_conn is None

    @patch("bietlejuice.base.spark.spark_session_factory.create_emr_spark_session")
    @patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    def test_conn_on_emr_uses_factory(self, mock_runtime_detector, mock_create_emr):
        mock_runtime_detector.is_emr.return_value = True
        expected = MagicMock()
        mock_create_emr.return_value = expected

        client = SparkClient(session_params={"spark.custom": "x"}, app_name="job_x")
        session = client.conn

        assert session is expected
        mock_create_emr.assert_called_once_with(
            "job_x", extra_configs={"spark.custom": "x"}
        )

    @pytest.mark.parametrize(
        "format, options, path",
        [
            ("parquet", {"path": "path/to/file"}, None),
            ("csv", {"path": "path/to/file", "header": True}, None),
            ("json", {"path": "path/to/file"}, None),
        ],
    )
    def test_get_data_from_external_source(
        self,
        format,
        options,
        path,
        mocked_get_data_from_external_source,
        mocked_spark_client,
    ):
        # arrange
        data = mocked_spark_client.create_dataframe([{"col1": "value", "col2": 123}])
        rdd = data.rdd.map(tuple)
        target_df = mocked_spark_client._session.read.json(rdd)
        mocked_get_data_from_external_source.load.return_value = target_df
        mocked_spark_client._session = mocked_get_data_from_external_source

        # act
        result_df = mocked_spark_client.get_data_from_external_source(
            format, options, path
        )

        # assert
        mocked_get_data_from_external_source.format.assert_called_once_with(format)
        mocked_get_data_from_external_source.options.assert_called_once_with(**options)
        mocked_get_data_from_external_source.load.assert_called_once_with(path=None)
        assert target_df.collect() == result_df.collect()

    @pytest.mark.parametrize(
        "format, options, path",
        [
            ("parquet", {"path": "path/to/file"}, "path/to/file"),
            ("csv", {"path": "path/to/file", "header": True}, "path/to/file"),
            ("json", {"path": "path/to/file"}, "path/to/file"),
        ],
    )
    def test_get_data_from_external_source_with_path(
        self,
        format,
        options,
        path,
        mocked_get_data_from_external_source,
        mocked_spark_client,
    ):
        # arrange
        data = mocked_spark_client.create_dataframe([{"col1": "value", "col2": 123}])
        rdd = data.rdd.map(tuple)
        target_df = mocked_spark_client._session.read.json(rdd)
        mocked_get_data_from_external_source.load.return_value = target_df
        mocked_spark_client._session = mocked_get_data_from_external_source

        # act
        result_df = mocked_spark_client.get_data_from_external_source(
            format, options, path
        )

        # assert
        mocked_get_data_from_external_source.format.assert_called_once_with(format)
        mocked_get_data_from_external_source.options.assert_called_once_with(**options)
        mocked_get_data_from_external_source.load.assert_called_once_with(path=path)
        assert target_df.collect() == result_df.collect()

    @pytest.mark.parametrize("format, options", [(None, {"path": "path/to/file"})])
    def test_get_data_from_external_source_invalid_format(
        self, format, options, mocked_spark_client
    ):
        # act and assert
        with pytest.raises(ValueError):
            mocked_spark_client.get_data_from_external_source(format, options)

    @pytest.mark.parametrize(
        "format, options", [("parquet", ("csv", "not valid options"))]
    )
    def test_get_data_from_external_source_invalid_options(
        self, format, options, mocked_spark_client
    ):
        # act and assert
        with pytest.raises(ValueError):
            mocked_spark_client.get_data_from_external_source(format, options)
