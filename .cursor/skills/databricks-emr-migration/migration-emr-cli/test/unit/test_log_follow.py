"""Unit tests for ``emr.log_follow`` (no real AWS calls)."""

from __future__ import annotations

import gzip
from io import BytesIO
from unittest.mock import MagicMock

import pytest

from emr.log_follow import (
    StepLogTailer,
    list_object_keys,
    step_logs_prefix,
)


def test_step_logs_prefix() -> None:
    bucket, prefix = step_logs_prefix(
        "s3://my-bucket/emr/logs/cli/",
        "j-CLUSTER",
        "s-STEP",
    )
    assert bucket == "my-bucket"
    assert prefix == "emr/logs/cli/j-CLUSTER/steps/s-STEP/"


def test_list_object_keys_from_paginator() -> None:
    paginator = MagicMock()
    paginator.paginate.return_value = iter(
        [
            {
                "Contents": [
                    {"Key": "emr/logs/cli/j-1/steps/s-1/stderr.gz"},
                    {"Key": "emr/logs/cli/j-1/steps/s-1/"},
                ]
            },
            {"Contents": [{"Key": "emr/logs/cli/j-1/steps/s-1/stdout.gz"}]},
        ]
    )
    s3 = MagicMock()
    s3.get_paginator.return_value = paginator
    keys = list_object_keys(s3, "my-bucket", "emr/logs/cli/j-1/steps/s-1/")
    assert keys == [
        "emr/logs/cli/j-1/steps/s-1/stderr.gz",
        "emr/logs/cli/j-1/steps/s-1/stdout.gz",
    ]


def test_tailer_prints_incremental_gzip() -> None:
    page = {"Contents": [{"Key": "pfx/stderr.gz"}]}
    paginator = MagicMock()
    paginator.paginate.side_effect = lambda **_kwargs: iter([page])
    s3 = MagicMock()
    s3.get_paginator.return_value = paginator

    gz1 = gzip.compress(b"line1\n")
    gz2 = gzip.compress(b"line1\nline2\n")
    s3.get_object.side_effect = [
        {"Body": BytesIO(gz1)},
        {"Body": BytesIO(gz2)},
    ]

    from io import StringIO

    tailer = StepLogTailer()
    buf = StringIO()
    import sys

    old = sys.stdout
    try:
        sys.stdout = buf
        assert tailer.poll(s3, "b", "pfx/") is True
        tailer.poll(s3, "b", "pfx/")
    finally:
        sys.stdout = old

    out = buf.getvalue()
    assert "line1" in out
    assert "line2" in out
    assert tailer.saw_any_key is True


def test_tailer_returns_false_when_prefix_empty() -> None:
    paginator = MagicMock()
    paginator.paginate.return_value = iter([{}])
    s3 = MagicMock()
    s3.get_paginator.return_value = paginator
    tailer = StepLogTailer()
    assert tailer.poll(s3, "b", "pfx/") is False
    assert tailer.saw_any_key is False


def test_poll_with_stall_warning_prints_after_three_empty_polls(
    capsys: pytest.CaptureFixture[str],
) -> None:
    paginator = MagicMock()
    paginator.paginate.return_value = iter([{}])
    s3 = MagicMock()
    s3.get_paginator.return_value = paginator
    tailer = StepLogTailer()
    for _ in range(2):
        assert tailer.poll_with_stall_warning(s3, "b", "pfx/") is False
    assert "No step log objects" not in capsys.readouterr().err
    assert tailer.poll_with_stall_warning(s3, "b", "pfx/") is False
    assert "No step log objects" in capsys.readouterr().err
