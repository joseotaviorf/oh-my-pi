"""Unit tests for ``emr.staging`` (mocked S3)."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from emr.config import validate_staging_uri
from emr.staging import (
    local_path_from_file_uri,
    resolve_local_uris_in_cfg,
    split_s3_uri,
    upload_local_file_to_staging,
)


def test_validate_staging_uri_normalizes_trailing_slash() -> None:
    assert validate_staging_uri("s3://my-bucket/emr/staging/") == (
        "s3://my-bucket/emr/staging/"
    )
    assert validate_staging_uri("s3://my-bucket/emr/staging") == (
        "s3://my-bucket/emr/staging/"
    )


def test_validate_staging_uri_rejects_bucket_only() -> None:
    with pytest.raises(ValueError, match="prefix"):
        validate_staging_uri("s3://bucket-only")


def test_validate_staging_uri_rejects_non_s3() -> None:
    with pytest.raises(ValueError, match="s3://"):
        validate_staging_uri("https://x/")


def test_split_s3_uri() -> None:
    assert split_s3_uri("s3://b/pre/fix/") == ("b", "pre/fix/")


def test_local_path_from_file_uri(tmp_path: Path) -> None:
    f = tmp_path / "job.py"
    f.write_text("# x", encoding="utf-8")
    uri = f.as_uri()
    assert local_path_from_file_uri(uri) == f.resolve()


def test_local_path_from_file_uri_missing_raises(tmp_path: Path) -> None:
    missing = tmp_path / "nope.py"
    uri = missing.as_uri()
    with pytest.raises(ValueError, match="readable"):
        local_path_from_file_uri(uri)


def test_resolve_local_uris_uploads_file_scheme(tmp_path: Path) -> None:
    py = tmp_path / "pi.py"
    py.write_text("print(1)", encoding="utf-8")
    uri = py.as_uri()

    cfg = {
        "region": "us-east-1",
        "staging_uri": "s3://artifacts/emr/staging/cli/",
        "s3_uri": uri,
    }
    mock_client = MagicMock()
    with patch("emr.staging.boto3.client", return_value=mock_client):
        resolve_local_uris_in_cfg(cfg)

    assert cfg["s3_uri"].startswith("s3://artifacts/")
    assert "/emr/staging/cli/" in cfg["s3_uri"]
    assert cfg["s3_uri"].endswith("/pi.py")
    mock_client.upload_file.assert_called_once()
    args, kwargs = mock_client.upload_file.call_args
    assert args[0] == str(py.resolve())
    assert args[1] == "artifacts"
    assert "pi.py" in args[2]


def test_resolve_local_uris_requires_staging_when_file(tmp_path: Path) -> None:
    py = tmp_path / "x.py"
    py.write_text("x", encoding="utf-8")
    cfg = {"s3_uri": py.as_uri()}
    with pytest.raises(ValueError, match="staging_uri is not set"):
        resolve_local_uris_in_cfg(cfg)


def test_upload_local_file_to_staging_key_includes_run_id(tmp_path: Path) -> None:
    f = tmp_path / "a.py"
    f.write_text("x", encoding="utf-8")
    mock_client = MagicMock()
    with patch("emr.staging.boto3.client", return_value=mock_client):
        out = upload_local_file_to_staging(
            f,
            "s3://buck/prefix/",
            region="us-east-1",
            run_id="deadbeef",
        )
    assert out == "s3://buck/prefix/deadbeef/a.py"
    mock_client.upload_file.assert_called_once_with(
        str(f.resolve()), "buck", "prefix/deadbeef/a.py"
    )
