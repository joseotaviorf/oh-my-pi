"""
Unit tests for load_vocs_machina_inference_status_raw.py.

Regression coverage for VOCS-34 dh-review: spark.createDataFrame(records)
with no explicit schema raises "can not infer schema from empty dataset"
when records is empty (e.g. quintoml's active-prompt manifest has zero
active prompts for a run). Same sys.modules-mocking convention as
test/dags/cross/base/spark_jobs/test_load_api_ingestion_raw.py -- pyspark and
the bietlejuice runtime deps aren't importable in this environment, so the
whole module tree is stubbed with MagicMock before importing the job.

active_prompts/backfill_day_range/success_marker_key/iter_partition_days/
build_snapshot_rows are mirrored byte-for-byte from
../../vocs_machina_planning.py (see this job's module docstring for why) --
the coverage below mirrors
packages/bietlejuice-airflow/test/unit/dags/for_rent/vocs_machina_planning/test_vocs_machina_planning.py's
equivalent tests, so the two copies can't silently drift apart unnoticed.
"""

import sys
from datetime import date
from unittest.mock import MagicMock

sys.modules["boto3"] = MagicMock()
sys.modules["pyspark"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["quintoandar_logger"] = MagicMock()
sys.modules["bietlejuice.base.db"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.clients.db_clients"] = MagicMock()
sys.modules["bietlejuice.loaders"] = MagicMock()
sys.modules["bietlejuice.loaders.s3_loader"] = MagicMock()
sys.modules["bietlejuice.services.metastore_services"] = MagicMock()

from dags.for_rent.vocs_machina_planning.spark_jobs import (  # noqa: E402
    load_vocs_machina_inference_status_raw as job,
)


class FakePaginator:
    """Fake boto3 list_objects_v2 paginator -- records the (Bucket, Prefix)
    it was called with and returns one page of Contents per call, enough to
    verify existing_marker_keys_for_days batches by unique day."""

    def __init__(self, keys_by_prefix):
        self.keys_by_prefix = keys_by_prefix
        self.paginate_calls = []

    def paginate(self, Bucket, Prefix):
        self.paginate_calls.append((Bucket, Prefix))
        keys = self.keys_by_prefix.get(Prefix, [])
        return [{"Contents": [{"Key": key} for key in keys]}]


class FakeS3Client:
    def __init__(self, keys_by_prefix):
        self._paginator = FakePaginator(keys_by_prefix)

    def get_paginator(self, operation_name):
        assert operation_name == "list_objects_v2"
        return self._paginator


def test_active_prompts_filters_inactive():
    manifest = {
        "prompts": [
            {"prompt_id": "p1", "active": True},
            {"prompt_id": "p2", "active": False},
        ]
    }
    assert [p["prompt_id"] for p in job.active_prompts(manifest)] == ["p1"]


def test_backfill_day_range_is_inclusive():
    today = date(2026, 7, 30)
    assert job.backfill_day_range(today, 2) == [
        date(2026, 7, 28),
        date(2026, 7, 29),
        date(2026, 7, 30),
    ]


def test_success_marker_key_zero_pads_month_and_day():
    # Regression: must match quintoml's vocs_machina/storage.py
    # build_partition_prefix + build_success_marker_uri byte-for-byte.
    key = job.success_marker_key("nps_churn", "abc123", date(2026, 5, 3))
    assert key == (
        "post-contract/vocs-machina/raw/"
        "year=2026/month=05/day=03/"
        "prompt_id=nps_churn/prompt_hash=abc123/_SUCCESS"
    )


def test_iter_partition_days_expands_each_active_prompt():
    prompts = [
        {"prompt_id": "p1", "prompt_hash": "h1", "backfill_days": 1},
        {"prompt_id": "p2", "prompt_hash": "h2", "backfill_days": 0},
    ]
    today = date(2026, 7, 30)
    assert job.iter_partition_days(prompts, today) == [
        (date(2026, 7, 29), "p1", "h1"),
        (date(2026, 7, 30), "p1", "h1"),
        (date(2026, 7, 30), "p2", "h2"),
    ]


def test_iter_partition_days_skips_prompt_missing_backfill_days():
    prompts = [
        {"prompt_id": "p1", "prompt_hash": "h1"},
        {"prompt_id": "p2", "prompt_hash": "h2", "backfill_days": 0},
    ]
    today = date(2026, 7, 30)
    assert job.iter_partition_days(prompts, today) == [(today, "p2", "h2")]


class TestBuildSnapshotRows:
    def test_marks_done_when_marker_key_present(self):
        day = date(2026, 5, 3)
        partition_days = [(day, "nps_churn", "abc123")]
        existing = {job.success_marker_key("nps_churn", "abc123", day)}

        rows = job.build_snapshot_rows(partition_days, existing)

        assert rows == [
            {
                "day": "2026-05-03",
                "prompt_id": "nps_churn",
                "prompt_hash": "abc123",
                "inference_status": "done",
            }
        ]

    def test_marks_missing_when_marker_key_absent(self):
        day = date(2026, 5, 3)
        rows = job.build_snapshot_rows(
            [(day, "nps_churn", "abc123")], existing_marker_keys=set()
        )
        assert rows[0]["inference_status"] == "missing"


class TestExistingMarkerKeysForDays:
    """existing_marker_keys_for_days batches by unique day: one paginate()
    call per distinct backfill day, matching the DAG-side S3Hook.list_keys
    batching contract (see the mirrored test in test_vocs_machina_planning.py)."""

    def test_one_paginate_call_per_unique_day(self):
        day1, day2 = date(2026, 5, 1), date(2026, 5, 2)
        prefix1 = "post-contract/vocs-machina/raw/year=2026/month=05/day=01/"
        prefix2 = "post-contract/vocs-machina/raw/year=2026/month=05/day=02/"
        s3_client = FakeS3Client(
            keys_by_prefix={
                prefix1: [f"{prefix1}prompt_id=p1/prompt_hash=h1/_SUCCESS"],
                prefix2: [],
            }
        )

        existing = job.existing_marker_keys_for_days(s3_client, [day1, day2])

        assert s3_client._paginator.paginate_calls == [
            ("data-science.s3.data.quintoandar.com.br", prefix1),
            ("data-science.s3.data.quintoandar.com.br", prefix2),
        ]
        assert existing == {f"{prefix1}prompt_id=p1/prompt_hash=h1/_SUCCESS"}

    def test_ignores_non_success_keys_under_the_same_prefix(self):
        day = date(2026, 5, 1)
        prefix = "post-contract/vocs-machina/raw/year=2026/month=05/day=01/"
        s3_client = FakeS3Client(
            keys_by_prefix={
                prefix: [
                    f"{prefix}prompt_id=p1/prompt_hash=h1/_SUCCESS",
                    f"{prefix}prompt_id=p1/prompt_hash=h1/part-00000.json",
                ]
            }
        )

        existing = job.existing_marker_keys_for_days(s3_client, [day])

        assert existing == {f"{prefix}prompt_id=p1/prompt_hash=h1/_SUCCESS"}

    def test_no_days_issues_no_calls(self):
        s3_client = FakeS3Client(keys_by_prefix={})
        assert job.existing_marker_keys_for_days(s3_client, []) == set()
        assert s3_client._paginator.paginate_calls == []


class TestReadActivePromptsManifest:
    def test_reads_and_parses_the_manifest_object(self):
        class FakeBody:
            def read(self):
                return b'{"prompts": []}'

        class FakeS3ClientForManifest:
            def get_object(self, Bucket, Key):
                assert Bucket == job.DATA_SCIENCE_BUCKET
                assert Key == job.VOCS_MACHINA_MANIFEST_KEY
                return {"Body": FakeBody()}

        assert job.read_active_prompts_manifest(FakeS3ClientForManifest()) == {
            "prompts": []
        }


class TestBuildInferenceStatusDataframe:
    def test_empty_rows_passes_an_explicit_schema(self):
        spark_client = MagicMock()

        job.build_inference_status_dataframe([], spark_client)

        spark_client.create_dataframe.assert_called_once_with(
            [], schema=job.INFERENCE_STATUS_SCHEMA
        )

    def test_nonempty_rows_still_passes_the_same_schema(self):
        spark_client = MagicMock()

        job.build_inference_status_dataframe(
            [
                {
                    "day": "2026-05-03",
                    "prompt_id": "nps_churn",
                    "prompt_hash": "abc123",
                    "inference_status": "done",
                }
            ],
            spark_client,
        )

        args, kwargs = spark_client.create_dataframe.call_args
        assert len(args[0]) == 1
        assert kwargs["schema"] == job.INFERENCE_STATUS_SCHEMA
