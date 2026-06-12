"""Unit tests for ``emr.log_dump`` (no real AWS calls)."""

from __future__ import annotations

import gzip
from io import BytesIO
from unittest.mock import MagicMock

import pytest

from emr.log_dump import bucket_and_key_prefix, dump_logs, sanitize_log_relative_path


@pytest.mark.parametrize(
    "raw",
    ("", "   ", "/abs", "a/../b", "../x", "foo/../../etc"),
)
def test_sanitize_log_relative_path_rejects(raw: str) -> None:
    with pytest.raises(ValueError):
        sanitize_log_relative_path(raw)


def test_sanitize_log_relative_path_ok() -> None:
    assert (
        sanitize_log_relative_path("  j-1/steps/s-1/stderr.gz  ")
        == "j-1/steps/s-1/stderr.gz"
    )
    assert sanitize_log_relative_path("./x/y") == "x/y"


def test_bucket_and_key_prefix() -> None:
    b, p = bucket_and_key_prefix(
        "s3://my-bucket/emr/logs/cli/", "j-ABC/steps/s-XYZ/stderr.gz"
    )
    assert b == "my-bucket"
    assert p == "emr/logs/cli/j-ABC/steps/s-XYZ/stderr.gz"


def test_dump_logs_prints_objects() -> None:
    paginator = MagicMock()
    paginator.paginate.return_value = iter(
        [
            {
                "Contents": [
                    {"Key": "emr/logs/cli/j-1/steps/s-1/stderr.gz"},
                ]
            }
        ]
    )
    s3 = MagicMock()
    s3.get_paginator.return_value = paginator
    gz = gzip.compress(b"err line\n")
    s3.get_object.return_value = {"Body": BytesIO(gz)}

    from io import StringIO

    buf = StringIO()
    dump_logs(
        s3,
        dump_logs_base_uri="s3://my-bucket/emr/logs/cli/",
        relative_path="j-1/steps/s-1/",
        stream=buf,
    )
    out = buf.getvalue()
    assert "=== s3://my-bucket/emr/logs/cli/j-1/steps/s-1/stderr.gz ===" in out
    assert "err line" in out
    s3.get_object.assert_called_once_with(
        Bucket="my-bucket", Key="emr/logs/cli/j-1/steps/s-1/stderr.gz"
    )


def test_dump_logs_raises_when_empty_prefix() -> None:
    paginator = MagicMock()
    paginator.paginate.return_value = iter([{}])
    s3 = MagicMock()
    s3.get_paginator.return_value = paginator

    with pytest.raises(ValueError, match="No S3 objects found"):
        dump_logs(s3, dump_logs_base_uri="s3://b/prefix/", relative_path="missing/")
