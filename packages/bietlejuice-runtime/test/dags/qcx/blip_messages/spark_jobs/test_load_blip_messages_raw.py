"""Pure-function unit tests for the Blip messages raw load job.

No Spark/Databricks runtime required: pyspark and bietlejuice modules are mocked
in ``sys.modules`` before importing the module under test.
"""

import sys
from unittest.mock import MagicMock

import pytest

sys.modules.setdefault("boto3", MagicMock())
sys.modules.setdefault("botocore", MagicMock())
sys.modules.setdefault("botocore.exceptions", MagicMock())
sys.modules.setdefault("pyspark", MagicMock())
sys.modules.setdefault("pyspark.sql", MagicMock())
sys.modules.setdefault("pyspark.sql.functions", MagicMock())
sys.modules.setdefault("pyspark.sql.types", MagicMock())
sys.modules.setdefault("pyspark.sql.window", MagicMock())
sys.modules.setdefault("quintoandar_logger", MagicMock())
sys.modules.setdefault("bietlejuice.base.db", MagicMock())
sys.modules.setdefault("bietlejuice.base.validation.spark_args", MagicMock())
sys.modules.setdefault("bietlejuice.clients.db_clients", MagicMock())
sys.modules.setdefault("bietlejuice.loaders.delta_loader", MagicMock())
sys.modules.setdefault("bietlejuice.services.configuration_service", MagicMock())
sys.modules.setdefault("bietlejuice.services.metastore_services", MagicMock())

from dags.qcx.blip_messages.spark_jobs.load_blip_messages_raw import (  # noqa: E402
    BACKFILL_SOURCE,
    INCREMENTAL_SOURCE,
    LedgerState,
    S3ObjectRef,
    _backfill_run_id,
    _discover_incremental,
    _expected_source,
    _incremental_unix,
    _is_message_object,
    _needs_processing,
)


class TestNeedsProcessing:
    def test_missing_key_needs_processing(self):
        ledger = LedgerState(
            success_etag_by_key={},
            failed_keys=set(),
            incremental_watermark_unix=None,
        )
        obj = S3ObjectRef(
            uri="s3://b/k.jsonl",
            bucket="b",
            key="k.jsonl",
            etag="abc",
            size_bytes=1,
        )
        assert _needs_processing(obj, ledger) is True

    def test_same_etag_success_is_skipped(self):
        ledger = LedgerState(
            success_etag_by_key={"k.jsonl": "abc"},
            failed_keys=set(),
            incremental_watermark_unix=None,
        )
        obj = S3ObjectRef(
            uri="s3://b/k.jsonl",
            bucket="b",
            key="k.jsonl",
            etag="abc",
            size_bytes=1,
        )
        assert _needs_processing(obj, ledger) is False

    def test_etag_change_needs_reprocess(self):
        ledger = LedgerState(
            success_etag_by_key={"k.jsonl": "old"},
            failed_keys=set(),
            incremental_watermark_unix=None,
        )
        obj = S3ObjectRef(
            uri="s3://b/k.jsonl",
            bucket="b",
            key="k.jsonl",
            etag="new",
            size_bytes=1,
        )
        assert _needs_processing(obj, ledger) is True

    def test_failed_key_needs_retry(self):
        ledger = LedgerState(
            success_etag_by_key={},
            failed_keys={"k.jsonl"},
            incremental_watermark_unix=None,
        )
        obj = S3ObjectRef(
            uri="s3://b/k.jsonl",
            bucket="b",
            key="k.jsonl",
            etag="abc",
            size_bytes=1,
        )
        assert _needs_processing(obj, ledger) is True


class TestExpectedSource:
    def test_backfill_prefix(self):
        assert (
            _expected_source("consorcio/blip/consorciois/backfill/1_2/batch_000.jsonl")
            == BACKFILL_SOURCE
        )

    def test_incremental_prefix(self):
        assert (
            _expected_source("consorcio/blip/consorciois/incremental/1786320000.jsonl")
            == INCREMENTAL_SOURCE
        )

    def test_unknown_prefix_raises(self):
        with pytest.raises(ValueError):
            _expected_source("consorcio/blip/other/file.jsonl")


class TestIsMessageObject:
    @pytest.mark.parametrize(
        "key,expected",
        [
            (
                "consorcio/blip/consorciois/backfill/1_2/batch_000.jsonl",
                True,
            ),
            (
                "consorcio/blip/consorciois/backfill/1_2/done.jsonl",
                False,
            ),
            (
                "consorcio/blip/consorciois/backfill/1_2/errors.jsonl",
                False,
            ),
            (
                "consorcio/blip/consorciois/incremental/1786320000.jsonl",
                True,
            ),
            (
                "consorcio/blip/consorciois/incremental/watermark.json",
                False,
            ),
            (
                "consorcio/blip/consorciois/incremental/1786320000.errors.jsonl",
                False,
            ),
        ],
    )
    def test_message_object_filter(self, key, expected):
        assert _is_message_object(key) is expected


class TestIncrementalUnixAndRunId:
    def test_incremental_unix(self):
        assert (
            _incremental_unix("consorcio/blip/consorciois/incremental/1786320000.jsonl")
            == 1786320000
        )

    def test_backfill_run_id(self):
        assert (
            _backfill_run_id(
                "consorcio/blip/consorciois/backfill/1783900800_1786320000/batch_1.jsonl"
            )
            == "1783900800_1786320000"
        )


class TestDiscoverIncrementalFiltering:
    def test_filters_below_watermark_unless_failed(self, monkeypatch):
        listed = [
            S3ObjectRef(
                uri="s3://b/p/incremental/10.jsonl",
                bucket="b",
                key="p/incremental/10.jsonl",
                etag="e10",
                size_bytes=1,
            ),
            S3ObjectRef(
                uri="s3://b/p/incremental/20.jsonl",
                bucket="b",
                key="p/incremental/20.jsonl",
                etag="e20",
                size_bytes=1,
            ),
            S3ObjectRef(
                uri="s3://b/p/incremental/30.jsonl",
                bucket="b",
                key="p/incremental/30.jsonl",
                etag="e30",
                size_bytes=1,
            ),
        ]

        def fake_list(**kwargs):
            return listed

        def fake_head(bucket, key):
            for ref in listed:
                if ref.key == key:
                    return ref
            raise AssertionError(key)

        import dags.qcx.blip_messages.spark_jobs.load_blip_messages_raw as job

        monkeypatch.setattr(job, "_list_s3_objects", fake_list)
        monkeypatch.setattr(job, "_head_object", fake_head)

        ledger = LedgerState(
            success_etag_by_key={"p/incremental/20.jsonl": "e20"},
            failed_keys={"p/incremental/10.jsonl"},
            incremental_watermark_unix=20,
        )
        refs = _discover_incremental(
            "s3://b/p",
            ledger,
        )
        keys = {ref.key for ref in refs}
        assert "p/incremental/10.jsonl" in keys  # failed retry
        assert "p/incremental/20.jsonl" in keys  # watermark re-head
        assert "p/incremental/30.jsonl" in keys  # newer
