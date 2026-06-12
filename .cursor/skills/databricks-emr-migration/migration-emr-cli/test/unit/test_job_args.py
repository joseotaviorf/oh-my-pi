"""Unit tests for ``emr.job_args``."""

from __future__ import annotations

import pytest

from emr.job_args import merged_job_script_args


def test_merged_job_script_args_none_when_empty() -> None:
    assert merged_job_script_args(None, ()) is None
    assert merged_job_script_args("", ()) is None
    assert merged_job_script_args("   ", ()) is None


def test_merged_job_script_args_shlex_only() -> None:
    out = merged_job_script_args(
        "--target-table db.t --target-path s3://b/p/",
        (),
    )
    assert out == ["--target-table", "db.t", "--target-path", "s3://b/p/"]


def test_merged_job_script_args_repeated_only() -> None:
    out = merged_job_script_args(None, ("--foo", "bar"))
    assert out == ["--foo", "bar"]


def test_merged_job_script_args_order_shlex_then_repeated() -> None:
    out = merged_job_script_args(
        "--a 1",
        ("--b", "2"),
    )
    assert out == ["--a", "1", "--b", "2"]


def test_merged_job_script_args_quoted_whitespace() -> None:
    out = merged_job_script_args(
        '--msg "hello world"',
        (),
    )
    assert out == ["--msg", "hello world"]


def test_merged_job_script_args_invalid_quote_raises() -> None:
    with pytest.raises(ValueError, match="invalid shell-style"):
        merged_job_script_args('"unclosed', ())
