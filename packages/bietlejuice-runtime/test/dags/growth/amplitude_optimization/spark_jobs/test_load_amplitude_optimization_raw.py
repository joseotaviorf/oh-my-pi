"""Pure-function unit tests for the amplitude_optimization raw load job.

No Spark/Databricks runtime required: pyspark and the bietlejuice modules the job
imports are mocked in ``sys.modules`` before importing the module under test, so the
tests exercise only the path-derivation and S3 prefix-listing logic.
"""

import sys
from unittest.mock import MagicMock

import pytest

sys.modules.setdefault("pyspark", MagicMock())
sys.modules.setdefault("pyspark.sql", MagicMock())
sys.modules.setdefault("pyspark.sql.functions", MagicMock())

for _mod in (
    "bietlejuice.base.api.api_enum",
    "bietlejuice.base.spark",
    "bietlejuice.base.validation.spark_args",
    "bietlejuice.clients.db_clients",
    "bietlejuice.jobs.common.raw_layer_loader",
    "bietlejuice.services.configuration_service",
    "quintoandar_logger",
):
    sys.modules.setdefault(_mod, MagicMock())

from dags.growth.amplitude_optimization.spark_jobs.load_amplitude_optimization_raw import (  # noqa: E402
    bucket_from_location,
    list_day_object_paths,
)


class _FakePaginator:
    """Minimal stand-in for boto3's list_objects_v2 paginator.

    Returns canned pages keyed by the requested ``Prefix`` and records every
    ``paginate`` call so tests can assert the exact server-side prefixes used.
    """

    def __init__(self, pages_by_prefix, calls):
        self._pages_by_prefix = pages_by_prefix
        self._calls = calls

    def paginate(self, Bucket, Prefix):
        self._calls.append((Bucket, Prefix))
        return list(self._pages_by_prefix.get(Prefix, [{"Contents": []}]))


class _FakeS3Client:
    def __init__(self, pages_by_prefix=None):
        self.pages_by_prefix = pages_by_prefix or {}
        self.calls = []

    def get_paginator(self, name):
        assert name == "list_objects_v2"
        return _FakePaginator(self.pages_by_prefix, self.calls)


def _page(*keys):
    return {"Contents": [{"Key": k} for k in keys]}


class TestBucketFromLocation:
    @pytest.mark.parametrize(
        "location, expected",
        [
            ("s3://5a-amplitude-events-prod/", "5a-amplitude-events-prod"),
            ("s3://my-bucket", "my-bucket"),
            ("s3://bucket/with/nested/path/", "bucket"),
            ("s3a://other-bucket/", "other-bucket"),
        ],
    )
    def test_extracts_bucket(self, location, expected):
        # Arrange / Act
        result = bucket_from_location(location)
        # Assert
        assert result == expected


class TestListDayObjectPaths:
    def test_uses_server_side_prefix_per_app_and_day(self):
        # Arrange
        bucket = "5a-amplitude-events-prod"
        client = _FakeS3Client(
            {
                "170698/170698_2026-06-03_": [
                    _page("170698/170698_2026-06-03_0.json.gz")
                ],
                "183047/183047_2026-06-03_": [
                    _page("183047/183047_2026-06-03_5.json.gz")
                ],
            }
        )
        # Act
        list_day_object_paths(client, bucket, ["170698", "183047"], "2026-06-03")
        # Assert: exact day-scoped prefixes, not the bare "{app}/" history prefix
        assert client.calls == [
            (bucket, "170698/170698_2026-06-03_"),
            (bucket, "183047/183047_2026-06-03_"),
        ]

    def test_returns_only_jsongz_as_full_s3_uris(self):
        # Arrange
        bucket = "5a-amplitude-events-prod"
        client = _FakeS3Client(
            {
                "170698/170698_2026-06-03_": [
                    _page(
                        "170698/170698_2026-06-03_0.json.gz",
                        "170698/170698_2026-06-03_0.json.gz.tmp",
                        "170698/170698_2026-06-03_MANIFEST",
                        "170698/170698_2026-06-03_1.json.gz",
                    )
                ],
            }
        )
        # Act
        paths = list_day_object_paths(client, bucket, ["170698"], "2026-06-03")
        # Assert: only .json.gz objects, prefixed with the s3 scheme + bucket
        assert paths == [
            "s3://5a-amplitude-events-prod/170698/170698_2026-06-03_0.json.gz",
            "s3://5a-amplitude-events-prod/170698/170698_2026-06-03_1.json.gz",
        ]

    def test_aggregates_across_pages_and_apps_in_order(self):
        # Arrange
        bucket = "b"
        client = _FakeS3Client(
            {
                "1/1_2026-06-03_": [
                    _page("1/1_2026-06-03_0.json.gz"),
                    _page("1/1_2026-06-03_1.json.gz"),
                ],
                "2/2_2026-06-03_": [_page("2/2_2026-06-03_0.json.gz")],
            }
        )
        # Act
        paths = list_day_object_paths(client, bucket, ["1", "2"], "2026-06-03")
        # Assert: every page of every app, app order preserved
        assert paths == [
            "s3://b/1/1_2026-06-03_0.json.gz",
            "s3://b/1/1_2026-06-03_1.json.gz",
            "s3://b/2/2_2026-06-03_0.json.gz",
        ]

    def test_app_with_no_objects_contributes_nothing(self):
        # Arrange: app "2" has no files that day (empty Contents)
        bucket = "b"
        client = _FakeS3Client(
            {
                "1/1_2026-06-03_": [_page("1/1_2026-06-03_0.json.gz")],
                "2/2_2026-06-03_": [{"Contents": []}],
            }
        )
        # Act
        paths = list_day_object_paths(client, bucket, ["1", "2"], "2026-06-03")
        # Assert
        assert paths == ["s3://b/1/1_2026-06-03_0.json.gz"]

    def test_no_apps_returns_empty(self):
        # Arrange
        client = _FakeS3Client()
        # Act
        paths = list_day_object_paths(client, "b", [], "2026-06-03")
        # Assert
        assert paths == []
        assert client.calls == []
