from unittest import mock
from unittest.mock import Mock

import pytest
import requests

from bietlejuice.base.pipeline import MetadataTypeEnum
from bietlejuice.metadata_propagator_pipeline.metadata_propagator_pipeline import (
    MetadataPropagatorPipeline,
)


class TestMetadataPropagatorPipeline:
    @mock.patch(
        "bietlejuice.metadata_propagator_pipeline.metadata_propagator_pipeline.post"
    )
    @mock.patch(
        "bietlejuice.metadata_propagator_pipeline.metadata_propagator_pipeline.MetadataPropagatorPipeline.build_metadata_propagator_payload"
    )
    def test_full_lineage_run_pipeline(
        self, mocked_build_metadata_propagator_payload, mocked_post
    ):
        # arrange
        host = Mock()
        database_name = Mock()
        table_name = Mock()
        endpoint = MetadataTypeEnum.FULL_CONTENT_LINEAGE
        expected_endpoint = f"{host}/fullContentLineage"

        mocked_build_metadata_propagator_payload.return_value = {}

        # run
        MetadataPropagatorPipeline(host, database_name, table_name, endpoint).run()

        # assert
        mocked_post.assert_called_once_with(expected_endpoint, json={})

    @mock.patch(
        "bietlejuice.metadata_propagator_pipeline.metadata_propagator_pipeline.post"
    )
    @mock.patch(
        "bietlejuice.metadata_propagator_pipeline.metadata_propagator_pipeline.MetadataPropagatorPipeline.build_metadata_propagator_payload"
    )
    def test_exception_run_pipeline(
        self, mocked_build_metadata_propagator_payload, mocked_post
    ):
        # arrange
        host = Mock()
        database_name = Mock()
        table_name = Mock()
        endpoint = MetadataTypeEnum.FULL_CONTENT_LINEAGE

        mocked_build_metadata_propagator_payload.return_value = {}
        mocked_response = Mock()
        mocked_response.raise_for_status.side_effect = Exception
        mocked_post.return_value = mocked_response

        # run 'n' assert
        with pytest.raises(Exception):
            MetadataPropagatorPipeline(host, database_name, table_name, endpoint).run()

    @mock.patch(
        "bietlejuice.metadata_propagator_pipeline.metadata_propagator_pipeline.post"
    )
    @mock.patch(
        "bietlejuice.metadata_propagator_pipeline.metadata_propagator_pipeline.MetadataPropagatorPipeline.build_metadata_propagator_payload"
    )
    def test_requests_exception_run_pipeline(
        self, mocked_build_metadata_propagator_payload, mocked_post
    ):
        # arrange
        host = Mock()
        database_name = Mock()
        table_name = Mock()
        endpoint = MetadataTypeEnum.FULL_CONTENT_LINEAGE

        mocked_build_metadata_propagator_payload.return_value = {}
        mocked_response = Mock()
        mocked_response.raise_for_status.side_effect = requests.RequestException(
            response=Mock()
        )
        mocked_post.return_value = mocked_response

        # run 'n' assert
        with pytest.raises(requests.RequestException):
            MetadataPropagatorPipeline(host, database_name, table_name, endpoint).run()
