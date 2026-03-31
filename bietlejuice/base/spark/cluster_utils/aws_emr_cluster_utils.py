"""
AWS-backed cluster utilities for EMR (Secrets Manager + S3 via boto3).

Exposes a ``dbutils``-like surface: ``.secrets.get(scope=..., key=...)`` and
``.fs.ls`` / ``.fs.head`` / ``.fs.rm`` for existing job code.

Default Secrets Manager secret id is ``{key}`` only (Databricks ``scope`` is not part
of the default id). Override with ``BIETL_SECRETS_MANAGER_SECRET_ID_TEMPLATE`` (e.g.
``{scope}/{key}`` or ``prefix/{key}``) when required.
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Any, List, Optional

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark.cluster_utils.fs_list_entry import FsListEntry

logger = QuintoAndarLogger("AwsEmrClusterUtils")

_DEFAULT_SECRETS_REGION = "us-east-1"
_DEFAULT_SECRET_ID_TEMPLATE = "{key}"


def _secrets_manager_region() -> str:
    return (
        os.environ.get("AWS_SECRETS_MANAGER_REGION")
        or os.environ.get("AWS_DEFAULT_REGION")
        or _DEFAULT_SECRETS_REGION
    )


def _s3_client_region() -> str:
    return os.environ.get("AWS_DEFAULT_REGION") or _DEFAULT_SECRETS_REGION


def _secret_id_for(scope: str, key: str) -> str:
    # Databricks passes scope+key; EMR secret naming may ignore scope unless the template uses {scope}.
    template = os.environ.get(
        "BIETL_SECRETS_MANAGER_SECRET_ID_TEMPLATE", _DEFAULT_SECRET_ID_TEMPLATE
    )
    return template.format(scope=scope, key=key)


def _parse_s3_uri(uri: str) -> tuple[str, str]:
    # Returns (bucket, key) with key possibly "" for bucket root.
    if not uri.startswith("s3://"):
        raise ValueError(f"Expected s3:// URI, got: {uri!r}")
    rest = uri[5:]
    slash = rest.find("/")
    if slash < 0:
        return rest, ""
    return rest[:slash], rest[slash + 1 :]


def _normalize_local_path(uri: str) -> str:
    if uri.startswith("file://"):
        return uri[7:]
    return uri


class AwsEmrClusterUtils:
    """
    EMR implementation: Secrets Manager for secrets, boto3 S3 + stdlib for paths.

    ``dbfs:`` URIs are not supported on EMR.
    """

    def __init__(self) -> None:
        self._secrets_client: Optional[Any] = None
        self._s3_client: Optional[Any] = None
        self.secrets = _SecretsFacade(self)
        self.fs = _FsFacade(self)

    def _get_secrets_client(self) -> Any:
        if self._secrets_client is None:
            self._secrets_client = boto3.client(
                "secretsmanager", region_name=_secrets_manager_region()
            )
        return self._secrets_client

    def _get_s3_client(self) -> Any:
        if self._s3_client is None:
            self._s3_client = boto3.client("s3", region_name=_s3_client_region())
        return self._s3_client

    def get_secret(self, scope: str, key: str) -> str:
        secret_id = _secret_id_for(scope, key)
        client = self._get_secrets_client()
        resp = client.get_secret_value(SecretId=secret_id)
        if "SecretString" in resp and resp["SecretString"] is not None:
            return resp["SecretString"]
        # Binary secrets: decode as UTF-8 for callers that expect str (same idea as Databricks string secrets).
        if "SecretBinary" in resp and resp["SecretBinary"] is not None:
            return resp["SecretBinary"].decode("utf-8", errors="replace")
        return ""

    def fs_ls(self, path: str) -> List[FsListEntry]:
        path = path.strip()
        if path.startswith("dbfs:"):
            raise ValueError(
                "dbfs: paths are not supported on EMR AwsEmrClusterUtils; use s3:// or local paths."
            )
        if path.startswith("s3://"):
            return self._s3_ls(path)
        return self._local_ls(_normalize_local_path(path))

    def _local_ls(self, path: str) -> List[FsListEntry]:
        base = Path(path).resolve()
        if not base.exists():
            logger.warning(f"m=fs_ls, path={path}, msg=path does not exist")
            return []
        entries: List[FsListEntry] = []
        for child in sorted(base.iterdir(), key=lambda p: p.name):
            is_dir = child.is_dir()
            full = str(child)
            if is_dir:
                name = child.name + "/"
                full_path = full if full.endswith("/") else full + "/"
            else:
                name = child.name
                full_path = full
            entries.append(FsListEntry(path=full_path, name=name, is_dir=is_dir))
        return entries

    def _s3_ls(self, uri: str) -> List[FsListEntry]:
        bucket, key = _parse_s3_uri(uri)
        prefix = key
        if prefix and not prefix.endswith("/"):
            prefix = prefix + "/"
        client = self._get_s3_client()
        paginator = client.get_paginator("list_objects_v2")
        entries: List[FsListEntry] = []
        seen: set[str] = set()

        # Delimiter="/" yields one level: CommonPrefixes = subdirs, Contents = files at this level only.
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix, Delimiter="/"):
            for cp in page.get("CommonPrefixes") or []:
                p = cp["Prefix"]
                if p in seen:
                    continue
                seen.add(p)
                name = p[len(prefix) :].rstrip("/") + "/"
                full_uri = f"s3://{bucket}/{p}"
                entries.append(FsListEntry(path=full_uri, name=name, is_dir=True))
            for obj in page.get("Contents") or []:
                obj_key = obj["Key"]
                if obj_key == prefix or obj_key.endswith("/"):
                    continue
                rel = obj_key[len(prefix) :] if prefix else obj_key
                # Skip nested keys when prefix is a folder: only list immediate children as files.
                if "/" in rel.rstrip("/"):
                    continue
                name = rel
                full_uri = f"s3://{bucket}/{obj_key}"
                entries.append(FsListEntry(path=full_uri, name=name, is_dir=False))
        return entries

    def fs_head(self, path: str, max_bytes: int) -> str:
        if not path.startswith("s3://"):
            p = Path(_normalize_local_path(path))
            data = p.read_bytes()[:max_bytes]
            return data.decode("utf-8", errors="replace")
        bucket, key = _parse_s3_uri(path)
        if key.endswith("/"):
            raise ValueError(f"fs.head requires an object key, not a prefix: {path}")
        client = self._get_s3_client()
        # S3 Range end is inclusive; fetch at most max_bytes without downloading the whole object.
        rng = f"bytes=0-{max_bytes - 1}"
        resp = client.get_object(Bucket=bucket, Key=key, Range=rng)
        return resp["Body"].read().decode("utf-8", errors="replace")

    def fs_rm(self, path: str, recurse: bool = False) -> bool:
        if path.startswith("dbfs:"):
            raise ValueError("dbfs: paths are not supported on EMR")
        if not path.startswith("s3://"):
            p = Path(_normalize_local_path(path))
            if p.is_dir():
                if recurse:
                    shutil.rmtree(p)
                else:
                    os.rmdir(p)
            else:
                p.unlink(missing_ok=True)
            return True
        bucket, key = _parse_s3_uri(path)
        client = self._get_s3_client()
        if not recurse:
            client.delete_object(Bucket=bucket, Key=key)
            return True
        prefix = key
        if prefix and not prefix.endswith("/"):
            prefix = prefix + "/"
        paginator = client.get_paginator("list_objects_v2")
        to_delete: List[dict] = []
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get("Contents") or []:
                to_delete.append({"Key": obj["Key"]})
        # delete_objects allows at most 1000 keys per request.
        for i in range(0, len(to_delete), 1000):
            batch = to_delete[i : i + 1000]
            if batch:
                client.delete_objects(Bucket=bucket, Delete={"Objects": batch})
        return True


class _SecretsFacade:
    """Thin wrapper so callers can use ``dbutils.secrets.get(scope, key)``."""

    def __init__(self, parent: AwsEmrClusterUtils) -> None:
        self._parent = parent

    def get(self, scope: str, key: str) -> str:
        return self._parent.get_secret(scope, key)


class _FsFacade:
    """Thin wrapper so callers can use ``dbutils.fs.ls|head|rm``."""

    def __init__(self, parent: AwsEmrClusterUtils) -> None:
        self._parent = parent

    def ls(self, path: str) -> List[FsListEntry]:
        return self._parent.fs_ls(path)

    def head(self, path: str, max_bytes: int) -> str:
        return self._parent.fs_head(path, max_bytes)

    def rm(self, path: str, recurse: bool = False) -> bool:
        return self._parent.fs_rm(path, recurse)
