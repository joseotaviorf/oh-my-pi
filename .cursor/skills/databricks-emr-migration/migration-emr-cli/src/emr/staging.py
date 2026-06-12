"""Upload local  artifacts to ``staging_uri`` (S3) before EMR submission."""

from __future__ import annotations

import sys
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from urllib.request import url2pathname

import boto3

from emr.config import validate_staging_uri


def local_path_from_file_uri(uri: str) -> Path:
    """Resolve a ``file://`` URI to an existing regular file path."""
    parsed = urlparse(uri.strip())
    if parsed.scheme.lower() != "file":
        raise ValueError(f"expected file:// URI, got {uri!r}")
    path = Path(url2pathname(parsed.path))
    resolved = path.resolve()
    if not resolved.is_file():
        raise ValueError(f"not a readable file: {resolved}")
    return resolved


def load_settings_staging_uri(cfg: dict[str, Any]) -> tuple[str, str | None]:
    staging_uri = validate_staging_uri(str(cfg["staging_uri"]))
    region = cfg.get("region")
    return staging_uri, str(region) if region else None


def split_s3_uri(uri: str) -> tuple[str, str]:
    """Split ``s3://bucket/key/parts`` into bucket and key (key may be empty)."""
    u = uri.strip()
    if not u.lower().startswith("s3://"):
        raise ValueError("expected s3:// URI")
    rest = u[5:]
    if "/" not in rest:
        return rest, ""
    bucket, key = rest.split("/", 1)
    if not bucket:
        raise ValueError("invalid s3:// URI (missing bucket)")
    return bucket, key


def upload_bytes_to_staging(
    data: bytes,
    staging_uri: str,
    key_suffix: str,
    *,
    region: str | None,
    content_type: str = "application/octet-stream",
) -> str:
    """Upload ``data`` under ``{staging_uri}{key_suffix}``. Returns full ``s3://`` URI."""
    normalized = validate_staging_uri(staging_uri)
    bucket, prefix = split_s3_uri(normalized)
    suffix = key_suffix.strip().lstrip("/")
    if not suffix:
        raise ValueError("key_suffix must be non-empty")
    key = f"{prefix}{suffix}"
    kwargs: dict[str, Any] = {}
    if region:
        kwargs["region_name"] = region
    client = boto3.client("s3", **kwargs)
    client.put_object(
        Bucket=bucket,
        Key=key,
        Body=data,
        ContentType=content_type,
    )
    return f"s3://{bucket}/{key}"


def upload_local_file_to_staging(
    local_path: Path,
    staging_uri: str,
    *,
    region: str | None,
    run_id: str,
    key_suffix: str | None = None,
) -> str:
    """Upload ``local_path`` under staging. Returns full ``s3://`` URI."""
    normalized = validate_staging_uri(staging_uri)
    bucket, prefix = split_s3_uri(normalized)
    if key_suffix:
        suffix = key_suffix.strip().lstrip("/")
    else:
        name = local_path.name
        if not name or name in (".", ".."):
            raise ValueError(f"invalid file name for staging: {name!r}")
        suffix = f"{run_id}/{name}"
    key = f"{prefix}{suffix}"
    kwargs: dict[str, Any] = {}
    if region:
        kwargs["region_name"] = region
    client = boto3.client("s3", **kwargs)
    client.upload_file(str(local_path), bucket, key)
    return f"s3://{bucket}/{key}"


def resolve_local_uris_in_cfg(cfg: dict[str, Any]) -> None:
    """Replace ``file://`` ``s3_uri`` / ``bootstrap_script_uri`` with S3 URIs under ``staging_uri``.

    Uses one ``run_id`` per call so job + bootstrap land under the same staging prefix for the run.
    Prints each staged target to stderr.
    """
    run_id = uuid.uuid4().hex
    region = cfg.get("region")

    def resolve(uri: str | None, label: str) -> str | None:
        if uri is None:
            return None
        u = uri.strip()
        if not u.lower().startswith("file://"):
            return u
        staging_prefix = cfg.get("staging_uri")
        if not staging_prefix:
            raise ValueError(
                f"{label} uses a local file but staging_uri is not set in settings YAML"
            )
        path = local_path_from_file_uri(u)
        s3_out = upload_local_file_to_staging(
            path,
            staging_prefix,
            region=str(region) if region else None,
            run_id=run_id,
        )
        print(f"Staged {label}: {path} -> {s3_out}", file=sys.stderr)
        return s3_out

    if cfg.get("s3_uri") is not None:
        cfg["s3_uri"] = resolve(cfg["s3_uri"], "s3_uri")
    bs = cfg.get("bootstrap_script_uri")
    if bs:
        cfg["bootstrap_script_uri"] = resolve(bs, "bootstrap_script_uri")
